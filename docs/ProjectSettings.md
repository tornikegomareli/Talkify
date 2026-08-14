# Project settings carried over from the deleted Tuist manifest

Values from the old `Project.swift`, needed when scaffolding the new plain `Talkify.xcodeproj`.

## Identity

- Bundle ID: `com.tgomareli.Talkify`
- Product: macOS app, deployment target macOS 26.0, `arm64` only
- Marketing version `0.1.0`, build `1`
- Category: `public.app-category.productivity`

## Info.plist keys that matter

- `LSUIElement` = true (menu-bar-only, no Dock icon)
- `NSMicrophoneUsageDescription` = "Talkify uses the microphone to transcribe your speech on this Mac."
- `NSSpeechRecognitionUsageDescription` = "Talkify converts your speech into text on this Mac."
- `NSPrincipalClass` = `NSApplication`
- `NSHighResolutionCapable` is not set: it is default-true for apps linked against modern SDKs, and Xcode's generated Info.plist has no `INFOPLIST_KEY_` for it

### Sparkle keys (Talkify/Info.plist)

The app target keeps `GENERATE_INFOPLIST_FILE = YES` **and** sets
`INFOPLIST_FILE = Talkify/Info.plist`; Xcode merges the generated keys into that
file. The plist exists only because Sparkle reads `SUPublicEDKey` from the bundle
and Xcode's `INFOPLIST_KEY_<name>` passthrough silently drops keys it does not
recognise — the Sparkle keys never reached the bundle that way.

- `SUFeedURL` = `https://raw.githubusercontent.com/tornikegomareli/Talkify/main/appcast.xml`
- `SUPublicEDKey` = public half of the EdDSA signing key; the private half is in the login Keychain, shared with Camus (Sparkle intends one key per developer)
- `SUEnableAutomaticChecks` = true, `SUScheduledCheckInterval` = 86400 (daily)
- `SUAllowsAutomaticUpdates` = true (automatic *downloading* still defaults off)

## Entitlements (Talkify.entitlements)

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

App Sandbox OFF (`ENABLE_APP_SANDBOX = NO`) — required for the CGEvent tap and AX insertion. Hardened Runtime ON.

## Build settings

Base: `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `DEAD_CODE_STRIPPING = YES`, `ONLY_ACTIVE_ARCH = NO`.

Deliberate deviations from the Xcode 26 template defaults: `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` and `SWIFT_APPROACHABLE_CONCURRENCY = NO`. The CarryOver components were written for classic strict concurrency with explicit `@MainActor` annotations; default-MainActor isolation would change the isolation of their non-annotated classes (e.g. the audio-thread callbacks in `MicrophoneInput`).

Debug signing: Apple Development, automatic, team `6SR4JWJD54`.

Release: Developer ID Application, manual, team `539293JFA3`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`, `LLVM_LTO = YES_THIN`, `SWIFT_COMPILATION_MODE = wholemodule`, `-O`, strip installed product, dwarf-with-dsym.
