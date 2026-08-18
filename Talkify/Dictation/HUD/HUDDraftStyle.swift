/// What happens to the draft when a Direct Dictation session ends.
///
/// The default keeps today's flow: recognition finishes and the text is
/// inserted into the focused control. The editable-draft variant holds the
/// finished draft in the HUD instead, where the user can edit it before
/// Return pastes, the Dictation Trigger starts a Replacement Dictation, or
/// Escape discards it.
enum HUDDraftStyle: String, CaseIterable {
  /// The session ends and the text is inserted, exactly as before.
  case pasteOnRelease = "Paste on Release"
  /// The draft stays in the HUD, editable, until Return or Escape.
  case editableDraft = "Editable Draft"
}
