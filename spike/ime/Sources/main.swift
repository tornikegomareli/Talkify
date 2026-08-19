import Cocoa
import InputMethodKit

/// THROWAWAY SPIKE. Answers whether a third-party input method can put
/// system-dictation-style provisional text into an arbitrary app's text field,
/// chunk by chunk, and how it behaves in the apps Talkify users actually live in.
///
/// It is not Talkify. It shares no code with Talkify. It exists to be installed,
/// tried in five or six apps, read, and deleted.
///
/// What it does: passes every keystroke straight through, so it behaves like a
/// plain US keyboard, except F13. F13 plays a scripted dictation: three growing
/// marked-text revisions, then a commit. That is the exact shape of what Apple's
/// own dictation does.

let kConnectionName = "TalkifySpike_Connection"

var server: IMKServer?

/// Every keystroke passes through untouched except the trigger. An input method
/// sits in the keyboard path for every app, so anything it does not understand
/// must reach the app unchanged or typing breaks system-wide.
@objc(TalkifySpikeController)
final class TalkifySpikeController: IMKInputController {
  /// The scripted revisions. Recognition revises itself in real speech, and the
  /// point of marked text is that a revision replaces what came before rather
  /// than appending to it.
  private static let script = [
    "the quick",
    "the quick brown",
    "the quick brown fox jumps",
  ]

  private static let committed = "the quick brown fox jumps over the lazy dog."

  private var step = 0

  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let event, event.type == .keyDown else { return false }

    // F13. Chosen because nothing else uses it, so a pass-through failure is
    // obvious rather than silently eating a key someone needed.
    guard event.keyCode == 105 else { return false }

    guard let client = sender as? IMKTextInput else {
      log("trigger pressed but the client is not IMKTextInput: \(type(of: sender as Any))")
      return true
    }

    log("trigger pressed. client=\(clientDescription(client))")
    step = 0
    revise(on: client)
    return true
  }

  /// Marked text, replaced in place three times, then committed. The whole
  /// question is whether the app under the cursor honours this.
  private func revise(on client: IMKTextInput) {
    guard step < Self.script.count else {
      client.insertText(
        Self.committed,
        replacementRange: NSRange(location: NSNotFound, length: 0)
      )
      log("committed \(Self.committed.count) characters")
      return
    }

    let text = Self.script[step]
    client.setMarkedText(
      text,
      selectionRange: NSRange(location: text.count, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    log("marked step \(step): \"\(text)\"")
    step += 1

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
      self?.revise(on: client)
    }
  }

  /// Which app received it, and whether it admits to supporting marked text.
  private func clientDescription(_ client: IMKTextInput) -> String {
    let bundle = client.bundleIdentifier() ?? "unknown"
    let supportsUnicode = client.supportsUnicode()
    let markedRange = client.markedRange()
    return "\(bundle) unicode=\(supportsUnicode) markedRange=\(markedRange)"
  }

  private func log(_ message: String) {
    NSLog("[IMESpike] %@", message)
  }
}

guard let identifier = Bundle.main.bundleIdentifier else {
  NSLog("[IMESpike] no bundle identifier")
  exit(1)
}
server = IMKServer(name: kConnectionName, bundleIdentifier: identifier)
NSLog("[IMESpike] server up as %@", identifier)
NSApplication.shared.run()
