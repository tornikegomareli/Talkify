# Borderless Settings surface

Talkify presents Settings in one fixed-size, centered borderless AppKit window hosting SwiftUI rather than a SwiftUI sheet or standard titled window. This matches the Wispr Flow-style modal surface while fitting a menu-bar-only app with no persistent parent window; the surface uses normal window level, explicit close/Escape dismissal, header dragging, internal scrolling, and one reusable window instance.
