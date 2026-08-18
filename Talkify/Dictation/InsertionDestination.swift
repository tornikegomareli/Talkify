/// Where a finished Direct Dictation session's text is delivered.
///
/// Inserting into the previously focused control is how every session ended
/// before this setting existed, and stays the default. The rawValues are
/// stored in UserDefaults, so renaming a case silently resets the preference.
enum InsertionDestination: String, CaseIterable {
  /// Paste into the captured target, then restore the previous clipboard.
  case insert
  /// Place the text on the clipboard and never paste, for users who want to
  /// decide where it lands.
  case clipboardOnly
  /// Paste into the captured target and leave the text on the clipboard,
  /// skipping the restore.
  case both

  var title: String {
    switch self {
    case .insert: "Insert into the app"
    case .clipboardOnly: "Copy to the clipboard"
    case .both: "Insert and copy"
    }
  }
}
