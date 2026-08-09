import AVFAudio
import Foundation
import Speech

actor SpeechRecognitionService {
    struct Update: Sendable {
        let finalizedText: String
        let volatileText: String

        var displayText: String {
            finalizedText + volatileText
        }
    }

    struct ResultAccumulator {
        private(set) var finalizedText = ""
        private(set) var volatileText = ""

        mutating func receive(_ text: String, isFinal: Bool) -> Update {
            if isFinal {
                finalizedText += text
                volatileText = ""
            } else {
                volatileText = text
            }

            return Update(
                finalizedText: finalizedText,
                volatileText: volatileText
            )
        }

        var completedText: String {
            finalizedText + volatileText
        }
    }

    enum RecognitionError: LocalizedError, Sendable {
        case unavailable
        case unsupportedLocale
        case missingAudioFormat
        case sessionAlreadyActive
        case noActiveSession

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Apple Speech is unavailable on this Mac."
            case .unsupportedLocale:
                "The selected language is not supported by Apple Speech."
            case .missingAudioFormat:
                "Apple Speech did not provide a compatible audio format."
            case .sessionAlreadyActive:
                "A dictation session is already active."
            case .noActiveSession:
                "No dictation session is active."
            }
        }
    }

    private struct PreparedSession: @unchecked Sendable {
        let locale: Locale
        let transcriber: SpeechTranscriber
        let analyzer: SpeechAnalyzer
        let audioFormat: AVAudioFormat
    }

    private struct ActiveSession {
        let prepared: PreparedSession
        let input: MicrophoneInput
        let continuation: AsyncStream<AnalyzerInput>.Continuation
        let resultTask: Task<String, any Error>
    }

    private var preparedSession: PreparedSession?
    private var activeSession: ActiveSession?
    private var reservedLocale: Locale?

    func prewarmPreferredLocale() async throws -> Locale {
        let locale = try await preferredLocale()
        try await prewarm(locale: locale)
        return locale
    }

    func start(
        updateHandler: @escaping @Sendable (Update) -> Void,
        failureHandler: @escaping @Sendable (String) -> Void,
        levelHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        guard activeSession == nil else {
            throw RecognitionError.sessionAlreadyActive
        }

        let prepared = try await takePreparedSession()
        try Task.checkCancellation()
        let (stream, continuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(64)
        )

        let resultTask = Task { () throws -> String in
            var accumulator = ResultAccumulator()

            for try await result in prepared.transcriber.results {
                let text = String(result.text.characters)
                updateHandler(accumulator.receive(text, isFinal: result.isFinal))
            }

            return accumulator.completedText
        }

        let input = MicrophoneInput(
            analyzerContinuation: continuation,
            failureHandler: { error in
                failureHandler(error.localizedDescription)
            },
            levelHandler: levelHandler
        )

        activeSession = ActiveSession(
            prepared: prepared,
            input: input,
            continuation: continuation,
            resultTask: resultTask
        )

        do {
            try await prepared.analyzer.start(inputSequence: stream)
            try Task.checkCancellation()
            try input.start(outputFormat: prepared.audioFormat)
            try Task.checkCancellation()
        } catch {
            activeSession = nil
            continuation.finish()
            input.stop()
            await prepared.analyzer.cancelAndFinishNow()
            resultTask.cancel()
            throw error
        }
    }

    func finish() async throws -> String {
        guard let session = activeSession else {
            throw RecognitionError.noActiveSession
        }
        activeSession = nil

        session.input.stop()
        session.continuation.finish()

        do {
            try await session.prepared.analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await session.resultTask.value
            prewarmAfterSession(locale: session.prepared.locale)
            return text
        } catch {
            session.resultTask.cancel()
            prewarmAfterSession(locale: session.prepared.locale)
            throw error
        }
    }

    func cancel() async {
        guard let session = activeSession else { return }
        activeSession = nil

        session.input.stop()
        session.continuation.finish()
        await session.prepared.analyzer.cancelAndFinishNow()
        session.resultTask.cancel()
        prewarmAfterSession(locale: session.prepared.locale)
    }

    func shutDown() async {
        await cancel()
        preparedSession = nil

        if let reservedLocale {
            await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }
    }

    private func takePreparedSession() async throws -> PreparedSession {
        if let preparedSession {
            self.preparedSession = nil
            return preparedSession
        }

        let locale = try await preferredLocale()
        return try await makePreparedSession(locale: locale)
    }

    private func prewarm(locale: Locale) async throws {
        guard preparedSession == nil else { return }
        preparedSession = try await makePreparedSession(locale: locale)
    }

    private func makePreparedSession(locale requestedLocale: Locale) async throws -> PreparedSession {
        guard SpeechTranscriber.isAvailable else {
            throw RecognitionError.unavailable
        }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw RecognitionError.unsupportedLocale
        }

        try await reserve(locale: locale)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // fastResults biases the transcriber towards responsiveness so
            // the live draft streams while the user is still speaking,
            // instead of appearing only at pauses.
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )

        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await installationRequest.downloadAndInstall()
        }

        let modules: [any SpeechModule] = [transcriber]
        guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules
        ) else {
            throw RecognitionError.missingAudioFormat
        }

        let options = SpeechAnalyzer.Options(
            priority: .high,
            modelRetention: .lingering
        )
        let analyzer = SpeechAnalyzer(modules: modules, options: options)
        try await analyzer.prepareToAnalyze(in: audioFormat)

        return PreparedSession(
            locale: locale,
            transcriber: transcriber,
            analyzer: analyzer,
            audioFormat: audioFormat
        )
    }

    private func preferredLocale() async throws -> Locale {
        if let storedIdentifier = UserDefaults.standard.string(forKey: "recognitionLocale"),
           let storedLocale = await SpeechTranscriber.supportedLocale(
               equivalentTo: Locale(identifier: storedIdentifier)
           ) {
            return storedLocale
        }

        if let currentLocale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            return currentLocale
        }

        if let englishLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "en-US")
        ) {
            return englishLocale
        }

        guard let firstLocale = await SpeechTranscriber.supportedLocales.first else {
            throw RecognitionError.unsupportedLocale
        }
        return firstLocale
    }

    private func reserve(locale: Locale) async throws {
        if reservedLocale == locale { return }

        if let reservedLocale {
            await AssetInventory.release(reservedLocale: reservedLocale)
        }

        try await AssetInventory.reserve(locale: locale)
        reservedLocale = locale
    }

    private func prewarmAfterSession(locale: Locale) {
        Task { [weak self] in
            try? await self?.prewarm(locale: locale)
        }
    }
}
