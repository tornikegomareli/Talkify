/// What sits at Intelligence's leading edge while listening, a Settings pick.
enum HUDIntelligenceCenterStyle: String, CaseIterable {
  /// A moving mesh of the palette that drips out of the notch, pinches off
  /// and settles (IntelligenceDrop.metal).
  case orb = "Orb"
  /// Talkify's ghost, filled with the palette: it floats down out of the
  /// notch, blinks, glances around, and opens its eyes wider while you speak.
  case ghost = "Ghost"
}
