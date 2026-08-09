import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsRuntimeState {
    var isDictating: Bool

    init(isDictating: Bool = false) {
        self.isDictating = isDictating
    }
}

enum SettingsSectionGroup: String, CaseIterable, Identifiable {
    case settings

    var id: Self { self }
    var title: String { rawValue.uppercased() }

    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.group == self }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case sounds
    case insights

    var id: Self { self }
    var group: SettingsSectionGroup { .settings }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .sounds: "Sounds"
        case .insights: "Insights"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: "Customize the Direct Dictation HUD"
        case .sounds: "Choose and preview Direct Dictation sounds"
        case .insights: "Review your local Direct Dictation activity"
        }
    }

    var icon: String {
        switch self {
        case .appearance: "sparkles"
        case .sounds: "waveform"
        case .insights: "chart.bar.xaxis"
        }
    }
}

/// The fixed Settings surface. Preferences persist through AppSettings,
/// active sessions keep their snapshot, and Insights reads aggregate usage.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let sounds: DictationHUDSounds
    let runtimeState: SettingsRuntimeState
    let usageTracker: UsageTracker
    let onClose: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSection: SettingsSection = .appearance

    static func showsWaveformOptions(for visual: HUDVoiceVisualStyle) -> Bool {
        visual == .waveform
    }

    static func showsGlowOptions(for visual: HUDVoiceVisualStyle) -> Bool {
        visual == .glow
    }


    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(onClose: onClose)

            if runtimeState.isDictating && selectedSection != .insights {
                ActiveSessionNotice()
            }

            HStack(spacing: 0) {
                SettingsSidebar(selectedSection: $selectedSection)

                Rectangle()
                    .fill(.white.opacity(contrast == .increased ? 0.18 : 0.08))
                    .frame(width: 1)

                ZStack(alignment: .topLeading) {
                    SettingsContent(
                        section: selectedSection,
                        settings: settings,
                        sounds: sounds,
                        usageTracker: usageTracker
                    )
                    .id(selectedSection)
                    .transition(.opacity)
                }
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.14),
                    value: selectedSection
                )
            }
        }
        .frame(width: 860, height: 600)
        .background {
            ZStack {
                SettingsTheme.background
                LinearGradient(
                    colors: [.white.opacity(0.035), .clear, .black.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(contrast == .increased ? 0.24 : 0.1), lineWidth: 1)
        }
        .tint(SettingsTheme.accent)
        .preferredColorScheme(.dark)
        .onExitCommand(perform: onClose)
    }
}

private struct SettingsHeader: View {
    let onClose: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 11) {
            // Close sits on the leading edge, where native macOS windows
            // keep their window controls.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(contrast == .increased ? 0.92 : 0.7))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.07), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 26, height: 26)
                .background(SettingsTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            Text("Settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(SettingsWindowDragHandle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(contrast == .increased ? 0.18 : 0.08))
                .frame(height: 1)
        }
    }
}

private struct ActiveSessionNotice: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(SettingsTheme.accent)
            Text("Changes apply to the next Direct Dictation session.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(contrast == .increased ? 0.92 : 0.72))
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 36)
        .background(SettingsTheme.accent.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsTheme.accent.opacity(contrast == .increased ? 0.35 : 0.18))
                .frame(height: 1)
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSection

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(SettingsSectionGroup.allCases) { group in
                SettingsSidebarGroup(title: group.title) {
                    ForEach(group.sections) { section in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                                selectedSection = section
                            }
                        } label: {
                            Label(section.title, systemImage: section.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(
                                    selectedSection == section
                                        ? .white
                                        : .white.opacity(contrast == .increased ? 0.82 : 0.62)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background {
                                    if selectedSection == section {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(.white.opacity(contrast == .increased ? 0.15 : 0.09))
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(SettingsTheme.accent)
                                                    .frame(width: 2)
                                                    .padding(.vertical, 7)
                                            }
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(.top, 20)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsTheme.sidebar)
    }
}

private struct SettingsSidebarGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(contrast == .increased ? 0.62 : 0.35))
                .padding(.horizontal, 18)

            VStack(spacing: 2) {
                content
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct SettingsContent: View {
    let section: SettingsSection
    @Bindable var settings: AppSettings
    let sounds: DictationHUDSounds
    let usageTracker: UsageTracker

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(section.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
                }

                switch section {
                case .appearance:
                    AppearanceSettings(settings: settings)
                case .sounds:
                    SoundsSettings(settings: settings, sounds: sounds)
                case .insights:
                    InsightsSettings(tracker: usageTracker)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AppearanceSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPreviewCard(settings: settings)

            SettingsCard(title: "Voice visual") {
                SettingsRow(
                    title: "While listening",
                    description: "The visual shown during Direct Dictation"
                ) {
                    Picker("While listening", selection: $settings.voiceVisual) {
                        ForEach(HUDVoiceVisualStyle.allCases, id: \.self) { visual in
                            Text(visual.rawValue).tag(visual)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150, alignment: .trailing)
                }


                if SettingsView.showsWaveformOptions(for: settings.voiceVisual) {
                    SettingsRow(
                        title: "Waveform style",
                        description: "The shape and motion of the waveform"
                    ) {
                        Picker("Waveform style", selection: $settings.waveformStyle) {
                            ForEach(HUDWaveformStyle.allCases, id: \.self) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150, alignment: .trailing)
                    }
                }

                if SettingsView.showsGlowOptions(for: settings.voiceVisual) {
                    SettingsRow(
                        title: "Glow palette",
                        description: "The colors used by the edge beam"
                    ) {
                        Picker("Glow palette", selection: $settings.glowPalette) {
                            ForEach(HUDGlowPalette.allCases, id: \.self) { palette in
                                Text(palette.rawValue).tag(palette)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150, alignment: .trailing)
                    }

                    SettingsRow(
                        title: "Glow center",
                        description: "The visual inside the edge beam"
                    ) {
                        Picker("Glow center", selection: $settings.glowCenter) {
                            ForEach(HUDGlowCenterStyle.settingsCases, id: \.self) { center in
                                Text(center.rawValue).tag(center)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150, alignment: .trailing)
                    }
                }
            }

            SettingsCard(title: "Motion and layout") {
                SettingsRow(
                    title: "Reveal style",
                    description: "How the HUD appears when Direct Dictation starts"
                ) {
                    Picker("Reveal style", selection: $settings.revealStyle) {
                        ForEach(HUDRevealStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150, alignment: .trailing)
                }

                SettingsRow(
                    title: "Long draft behavior",
                    description: "How the HUD handles longer dictated text"
                ) {
                    Picker("Long draft behavior", selection: $settings.longDraftStyle) {
                        ForEach(HUDLongDraftStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150, alignment: .trailing)
                }
            }
        }
    }
}

private struct SoundsSettings: View {
    @Bindable var settings: AppSettings
    let sounds: DictationHUDSounds

    @State private var isPreviewing = false
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        SettingsCard(title: "Direct Dictation") {
            SettingsRow(
                title: "Sound set",
                description: "The sounds used when a session begins and ends"
            ) {
                Picker("Sound set", selection: $settings.soundSet) {
                    ForEach(DictationSoundSet.settingsCases, id: \.self) { set in
                        Text(set.rawValue).tag(set)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150, alignment: .trailing)
            }

            SettingsRow(
                title: "Preview",
                description: "Play the selected begin and end sounds"
            ) {
                Button {
                    playPreview()
                } label: {
                    Text(isPreviewing ? "Playing…" : "Play preview")
                }
                .buttonStyle(SettingsButtonStyle())
                .disabled(
                    isPreviewing || !sounds.hasPreviewSounds(for: settings.soundSet)
                )
            }
        }
        .onChange(of: settings.soundSet) {
            cancelPreview()
        }
        .onDisappear {
            cancelPreview()
        }
    }

    private func playPreview() {
        let set = settings.soundSet
        let delay = max(sounds.beginDuration(for: set), 0) + 0.1
        isPreviewing = true
        sounds.playBegin(using: set)

        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            sounds.playEnd(using: set)
            isPreviewing = false
            previewTask = nil
        }
    }

    private func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        sounds.stopAll()
        isPreviewing = false
    }
}

private struct SettingsPreviewCard: View {
    let settings: AppSettings

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var content = DictationHUDContent()
    /// Runs the one-shot demos below; a new demo cancels the previous one.
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live preview")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Changes appear here immediately")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
                }
                Spacer()
                Circle()
                    .fill(SettingsTheme.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: SettingsTheme.accent, radius: reduceMotion ? 0 : 7)
            }

            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color(red: 0.055, green: 0.065, blue: 0.09), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )

                DictationHUDShellView(
                    screen: HUDPreviewScreen.notched,
                    settings: settings.sessionSettings,
                    content: content
                )
                .scaleEffect(0.48, anchor: .top)
                .frame(width: 300, height: 105, alignment: .top)
                .clipped()
            }
            .frame(height: 118)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(contrast == .increased ? 0.2 : 0.07), lineWidth: 1)
            }
        }
        .padding(16)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(contrast == .increased ? 0.22 : 0.1), lineWidth: 1)
        }
        // The preview idles in a revealed listening state, where these two
        // picks have nothing to show: reveal style only exists during the
        // reveal transition, and long-draft behavior only exists while the
        // text band wraps. Changing either plays a short demo of it.
        .onChange(of: settings.revealStyle) {
            replayReveal()
        }
        .onChange(of: settings.longDraftStyle) {
            demoLongDraft()
        }
        .task(id: reduceMotion) {
            content.isRevealed = true
            content.showsVoiceVisual = true
            content.isAudioAlive = true
            content.text = "Direct Dictation preview"
            content.sessionEpoch += 1

            if reduceMotion {
                content.audioLevel = 0.2
                content.levelHistory = [Float](repeating: 0.2, count: HUDWaveformView.barCount)
                return
            }

            var time = 0.0
            while !Task.isCancelled {
                let level = 0.1 + max(0, sin(time * 4.8)) * 0.28
                content.audioLevel = level
                content.levelHistory.removeFirst()
                content.levelHistory.append(Float(level))
                time += 0.07
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }

    /// Replays the reveal: retract, wait out the dismiss, descend again with
    /// the freshly picked style.
    private func replayReveal() {
        demoTask?.cancel()
        demoTask = Task { @MainActor in
            // A cancelled long-draft demo may have left its long text up.
            content.text = "Direct Dictation preview"
            content.showsVoiceVisual = true
            content.isRevealed = false
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            content.isRevealed = true
        }
    }

    /// Shows the picked long-draft behavior: the text band only renders when
    /// no visual replaces it, so the visual steps aside while a long draft
    /// wraps, truncates, or shrinks, then listening resumes.
    private func demoLongDraft() {
        demoTask?.cancel()
        demoTask = Task { @MainActor in
            // A cancelled reveal replay may have left the shape retracted.
            content.isRevealed = true
            content.showsVoiceVisual = false
            let longDraft = "A long draft that outgrows a single line shows "
                + "how the HUD handles longer dictated text while you speak"
            content.text = longDraft
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            content.text = "Direct Dictation preview"
            content.showsVoiceVisual = true
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.44))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(contrast == .increased ? 0.22 : 0.09), lineWidth: 1)
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder let control: Control

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(contrast == .increased ? 0.16 : 0.07))
                .frame(height: 1)
        }
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.1), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct SettingsWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SettingsWindowDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

enum SettingsTheme {
    static let background = Color(red: 0.025, green: 0.027, blue: 0.035)
    static let sidebar = Color(red: 0.035, green: 0.038, blue: 0.049)
    static let card = Color(red: 0.065, green: 0.069, blue: 0.087)
    static let accent = Color(red: 0.36, green: 0.58, blue: 1.0)
}

#Preview {
    let settings = AppSettings.previewStore()
    SettingsView(
        settings: settings,
        sounds: DictationHUDSounds(),
        runtimeState: SettingsRuntimeState(),
        usageTracker: UsageTracker(store: UsageStore(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "TalkifySettingsPreview-usage.json")
        )),
        onClose: {}
    )
}
