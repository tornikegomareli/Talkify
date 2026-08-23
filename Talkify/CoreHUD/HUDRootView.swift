import SwiftUI

/// What the HUD window hosts. Dictation and Drop Transcription never share the
/// shape, so the root picks one; hosting a single root view keeps the window's
/// content view stable while what it shows changes.
struct HUDRootView: View {
  let screen: HUDScreenSnapshot
  let settings: DictationSessionSettings
  let content: DictationHUDContent
  let drop: DropHUDContent
  let stage: HUDStage?
  var onDrop: (Int) -> Void = { _ in }
  var onCardEvent: (HUDCardEvent) -> Void = { _ in }

  init(
    screen: HUDScreenSnapshot,
    settings: DictationSessionSettings,
    content: DictationHUDContent,
    drop: DropHUDContent,
    stage: HUDStage? = nil,
    onDrop: @escaping (Int) -> Void = { _ in },
    onCardEvent: @escaping (HUDCardEvent) -> Void = { _ in }
  ) {
    self.screen = screen
    self.settings = settings
    self.content = content
    self.drop = drop
    self.stage = stage
    self.onDrop = onDrop
    self.onCardEvent = onCardEvent
  }

  var body: some View {
    if drop.mode == .none {
      DictationHUDShellView(screen: screen, settings: settings, content: content, stage: stage)
    } else {
      DropHUDView(
        screen: screen,
        settings: settings,
        drop: drop,
        onDrop: onDrop,
        onCardEvent: onCardEvent
      )
    }
  }
}
