# Capturing other applications' audio on macOS 26

Research notes for **Live Captions** and any future **Meeting Transcript**. Everything here comes from
Apple documentation, the macOS SDK headers on this machine, Apple sample code, WWDC session
transcripts, or a direct measurement made on this machine. Claims I could not source are marked as
unverified.

Header paths are relative to the installed SDK:

```
SDK=$(xcrun --show-sdk-path)
# /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
# xcrun --sdk macosx --show-sdk-version -> 26.5
```

## 1. The supported routes

There are two. Core Audio process taps, and ScreenCaptureKit. macOS 26 adds no third one.

### Core Audio process taps

The whole API is two functions:

```objc
extern OSStatus
AudioHardwareCreateProcessTap(CATapDescription* inDescription,
                              AudioObjectID*  outTapID)   API_AVAILABLE(macos(14.2)) API_UNAVAILABLE(ios, watchos, tvos);

extern OSStatus
AudioHardwareDestroyProcessTap(AudioObjectID inTapID)     API_AVAILABLE(macos(14.2)) API_UNAVAILABLE(ios, watchos, tvos);
```

`$SDK/System/Library/Frameworks/CoreAudio.framework/Headers/AudioHardwareTapping.h`. The
documentation page agrees on macOS 14.2
(<https://developer.apple.com/documentation/coreaudio/audiohardwarecreateprocesstap(_:_:)>).

`CATapDescription` itself is annotated `API_AVAILABLE(macos(12.0), ios(15.0))` and `CATapMuteBehavior`
`API_AVAILABLE(macos(13.0), ios(16.0))`, in
`$SDK/System/Library/Frameworks/CoreAudio.framework/Headers/CATapDescription.h`. The class therefore
predates the function that consumes it by two releases. Treat 14.2 as the real floor, because before
that there is no way to create a tap.

A description selects its scope through the initializer, all declared in `CATapDescription.h`:

| Initializer | Scope |
| --- | --- |
| `initStereoMixdownOfProcesses:` / `initMonoMixdownOfProcesses:` | only the listed process objects, mixed down |
| `initStereoGlobalTapButExcludeProcesses:` / `initMonoGlobalTapButExcludeProcesses:` | every process that outputs audio, minus the listed ones |
| `initWithProcesses:andDeviceUID:withStream:` | the listed processes, restricted to one stream of one output device |
| `initExcludingProcesses:andDeviceUID:withStream:` | everything except the listed processes, on one stream of one output device |

So both per-application and system-wide capture come from the same API. For the device-scoped
initializers the header states: "The format of the tap will match the format of this stream."

`processes` holds `AudioObjectID` values for process objects, not PIDs. You translate with
`kAudioHardwarePropertyTranslatePIDToProcessObject` (`'id2p'`), passing the `pid_t` as the qualifier.
The header warns that an unknown PID is not an error: "this property will return
`kAudioObjectUnknown` as the value of the property"
(`$SDK/System/Library/Frameworks/CoreAudio.framework/Headers/AudioHardware.h`, near line 589). Note
that none of the tap, process, sub-tap or aggregate constants in `AudioHardware.h` carry availability
annotations, and the documentation page for
`kAudioHardwarePropertyTranslatePIDToProcessObject` lists no introduced version
(<https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertytranslatepidtoprocessobject>).
Availability for this whole area has to be inferred from the two functions above.

A tap is not readable on its own. You add it to an aggregate device and drive that device with an
IOProc. Apple's article spells out the sequence: create the tap, create the aggregate with
`AudioHardwareCreateAggregateDevice`, read `kAudioTapPropertyUID` from the tap, then set
`kAudioAggregateDevicePropertyTapList` on the aggregate to an array containing that UID
(<https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps>).
The relevant composition keys are `kAudioAggregateDeviceTapListKey` (`"taps"`),
`kAudioAggregateDeviceIsPrivateKey` (`"private"`) and `kAudioAggregateDeviceTapAutoStartKey`
(`"tapautostart"`), all in `AudioHardware.h`. Two of those matter for a menu-bar app:

- Private aggregate: "a value of 1 means that the AudioAggregateDevice is private to the process that
  created it. Note that a private AudioAggregateDevice is not persistent across launches of the
  process that created it." A private aggregate does not appear in the user's Sound settings.
- Auto-start: "calling AudioDeviceStart with the aggregate device will wait until a tapped process
  begins receiving its first audio from any tapped applications. The composition must also include
  the private key so that the aggregate is private to the process that created it."

The tap's own format is a runtime read, not a constant: `kAudioTapPropertyFormat` returns an
`AudioStreamBasicDescription`, described as "the format of that data that will be accessible in any
aggregate device that contains the tap". Apple's sample reads it and prints channels and sample rate
(`AudioTapSample/AudioTap.swift`, lines 44-51 of the downloaded sample). Read it; do not assume 48 kHz
stereo.

Process objects expose `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID`,
`kAudioProcessPropertyIsRunning`, `kAudioProcessPropertyIsRunningInput` and
`kAudioProcessPropertyIsRunningOutput`. `kAudioHardwarePropertyProcessObjectList` (`'prs#'`) lists
"the Process objects for all client processes currently connected to the system". That list is how you
build a source picker.

### What macOS 26 added

Two properties on `CATapDescription`, and nothing else in this area:

```objc
@property (atomic, copy, readwrite) NSArray<NSString*>* bundleIDs
API_AVAILABLE(macos(26.0));

@property (atomic, readwrite, getter=isProcessRestoreEnabled) BOOL processRestoreEnabled
API_AVAILABLE(macos(26.0));
```

`bundleIDs` is "an Array of Strings where each String holds the bundle ID of a process to tap or
exclude". `processRestoreEnabled` is "True if this tap should save tapped processes by bundle ID when
they exit, and restore them to the tap when they start up again"
(`CATapDescription.h`; <https://developer.apple.com/documentation/coreaudio/catapdescription/bundleids>).
Apple's sample defaults `isProcessRestoreEnabled` to `true` in its own tap configuration
(`AudioTapSample/AudioTap.swift`, `struct TapConfig`).

Both matter for a long-lived source: a browser or a conferencing app that respawns its audio helper
process no longer needs the tap rebuilt.

ScreenCaptureKit gained no audio API in macOS 26. Grepping the SDK headers for `macos(26` in
`ScreenCaptureKit.framework/Headers/` returns only `SCScreenshotManager` and one HDR preset, and the
framework's own change list stops at June 2024
(<https://developer.apple.com/documentation/updates/screencapturekit>).

### ScreenCaptureKit audio

Audio is a property of a screen-capture stream, added in macOS 13. From
`$SDK/System/Library/Frameworks/ScreenCaptureKit.framework/Headers/SCStream.h`:

```objc
@property(nonatomic, assign) BOOL capturesAudio API_AVAILABLE(macos(13.0));               // default NO
@property(nonatomic, assign) NSInteger sampleRate API_AVAILABLE(macos(13.0));             // default 48000
@property(nonatomic, assign) NSInteger channelCount API_AVAILABLE(macos(13.0));           // default 2
@property(nonatomic, assign) BOOL excludesCurrentProcessAudio API_AVAILABLE(macos(13.0)); // default NO
@property(nonatomic, assign) BOOL captureMicrophone API_AVAILABLE(macos(15.0));           // default NO
```

Samples arrive as `SCStreamOutputTypeAudio` (macOS 13), described in the same header as "a sample
buffer that is wrapping an audio buffer list. The format of the audio buffer is based on sampleRate
and channelCount set in SCStreamConfiguration." Unlike a tap, you name the output format instead of
discovering it.

Two things constrain this route. First, the stream is still a screen-capture stream: you build it from
an `SCContentFilter` over displays, windows or applications, and Apple's own sample sets `width`,
`height` and `minimumFrameInterval` alongside the audio flags
(<https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>). I
found no primary source describing an audio-only `SCStream`, and no property that disables the video
path. Unverified whether one is possible.

Second, the filter granularity does not apply to audio. From WWDC22 session 10155, *Take
ScreenCaptureKit to the next level*, at [4:13]:

> ScreenCaptureKit's audio capture policy on the other hand always works at the app level. When a
> single window filter is used, all the audio content from the application that contains the window
> will be captured, even from those windows that are not present in the video output.

(<https://developer.apple.com/videos/play/wwdc2022/10155>)

`SCContentSharingPicker` (macOS 14) is the system picker for choosing what to capture; Apple's
guidance is "Avoid creating your own sharing picker. Use the picker provided by the shared static
property" (<https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker>).

### Comparison

| | Core Audio process tap | ScreenCaptureKit |
| --- | --- | --- |
| Per-application audio | Yes, by process object or (26.0) bundle ID | Yes, by `SCContentFilter` application, app-level only |
| System-wide audio | Yes, global tap with an exclusion list | Yes, capture a display; audio is not filtered by window |
| Exclude own audio | Yes, exclusion list | Yes, `excludesCurrentProcessAudio` |
| Output format | Discovered from `kAudioTapPropertyFormat` | Requested via `sampleRate` / `channelCount` |
| Delivery | Aggregate-device IOProc, in the HAL IO cycle | `CMSampleBuffer` on a dispatch queue you supply |
| Screen recording permission | No | Yes |
| Also needs video machinery | No | Yes, a filter and frame configuration |

Latency: neither route publishes a figure. What is documented is that a tap participates in the HAL's
IO cycle and that a sub-tap can be given deliberate extra latency:
`kAudioSubTapExtraInputLatencyKey` ("latency-in") and `kAudioSubTapExtraOutputLatencyKey`
("latency-out"), "the total number of frames of additional latency" (`AudioHardware.h`). ScreenCaptureKit's
documented latency discussion is entirely about video surfaces and `queueDepth` (WWDC22 10155 at
[26:15] onward). Any latency comparison would have to be measured, not read.

## 2. Permissions and user-facing cost

The two routes hit two different TCC services. Both service identifiers appear in the macOS 26
privacy pane binary, `kTCCServiceAudioCapture` and `kTCCServiceScreenCapture`
(`strings /System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/MacOS/SecurityPrivacyExtension`).

**A tap triggers system audio recording.** Apple's article states it twice, as an Important aside:

> To capture audio with a tap, you need to include the `NSAudioCaptureUsageDescription` key in your
> Info.plist file, along with a message that tells the user why the app is requesting access to
> capture audio. The first time you start recording from an aggregate device that contains a tap, the
> system prompts you to grant the app system audio recording permission.

(<https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps>)

`NSAudioCaptureUsageDescription` is "a message that tells people why your app is requesting access to
capture system audio on macOS", introduced in macOS 14.2
(<https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription>).
Apple's sample ships exactly one key in its `Info.plist`:

```xml
<key>NSAudioCaptureUsageDescription</key>
<string>This app requires access to application audio</string>
```

The pane is **System Settings > Privacy & Security > System Audio Recording**. The localized strings
in the privacy pane are unambiguous
(`/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable`):

```
AUDIO_CAPTURE            = System Audio Recording
AUDIO_CAPTURE_HEADER     = System Audio Recording Only
AUDIO_CAPTURE_SUMMARY    = Allow the applications below to access and record your system audio.
AUDIO_CAPTURE_EMPTY_APP_LIST = Applications that have requested access to record your app audio will appear here.
```

This is a separate list from the screen one, which uses `SCREEN_CAPTURE_HEADER = Screen & System Audio
Recording`. So a tap-based feature never appears in the screen-recording list and never asks for
screen recording.

**ScreenCaptureKit triggers screen recording.** Apple's sample says: "The first time you run this
sample, the system prompts you to grant the app Screen Recording permission. After you grant
permission, you need to restart the app to enable capture"
(<https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>). The
user-facing pane is Privacy & Security > Screen & System Audio Recording
(<https://support.apple.com/guide/mac-help/control-access-to-screen-and-system-audio-recording-mchld6aa7d23/mac>).
Refusal surfaces as `SCStreamErrorUserDeclined` (-3801) and a missing-entitlement case as
`SCStreamErrorMissingEntitlements` (-3803), in
`$SDK/System/Library/Frameworks/ScreenCaptureKit.framework/Headers/SCError.h`.

There is no usage-description key for screen recording. `CGPreflightScreenCaptureAccess()` and
`CGRequestScreenCaptureAccess()` exist since macOS 10.15 for querying and requesting it
(<https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()>).

**There is no public API to query the system-audio permission.** I searched the CoreAudio and
AudioToolbox headers in the 26.5 SDK for any authorization function and found none.
`AVCaptureDevice.authorizationStatus(for: .audio)` covers microphone hardware
(`kTCCServiceMicrophone`), a different service; the header restricts it to `AVMediaTypeVideo` or
`AVMediaTypeAudio` and describes it as "the underlying hardware supporting the media type"
(`AVFoundation.framework/Headers/AVCaptureDevice.h`, line 2030). The documented behavior is that the
prompt appears when capture starts, which means a tap-based feature cannot pre-flight its own
permission with public API. AudioCap solves this with private TCC API behind a build flag, and says so
(<https://github.com/insidegui/AudioCap>).

**Sandbox and entitlements.** Both of Apple's samples are sandboxed. The tap sample carries:

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.assets.music.read-write</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
```

The ScreenCaptureKit sample carries only `com.apple.security.app-sandbox` and
`com.apple.security.files.user-selected.read-only`. So: a tap works inside the sandbox with the
audio-input entitlement, and ScreenCaptureKit works inside the sandbox with no capture-specific
entitlement at all. Neither route needs a special Apple-granted entitlement. Talkify is unsandboxed
(`ENABLE_APP_SANDBOX = NO`, `docs/ProjectSettings.md`) and already declares
`com.apple.security.device.audio-input` in `Talkify.entitlements`, so the tap route adds one
`Info.plist` key and nothing else.

Notarization is orthogonal; nothing in either framework's documentation ties capture to it.

**Background source, sleeping display.** Not properly documented for either route. What I can source:
a tap is scoped to a process object, and `kAudioProcessPropertyIsRunningOutput` reports whether that
process has an active output stream, with no reference to window or activation state
(`AudioHardware.h`). Also `kAudioHardwarePropertySleepingIsAllowed`: "A UInt32 where 1 means that the
process will allow the CPU to idle sleep even if there is audio IO in progress", which implies an
active tap holds off idle sleep by default. I found no primary statement about display sleep for
either route, and none about whether ScreenCaptureKit keeps delivering audio when its captured display
sleeps. Unverified; needs a measurement.

## 3. Feeding it to Apple Speech

`SpeechAnalyzer` takes audio through `AnalyzerInput`, and `AnalyzerInput` takes an `AVAudioPCMBuffer`.
Nothing about it is microphone-specific:

```swift
public struct AnalyzerInput : @unchecked Swift.Sendable {
  public init(buffer: AVFAudio.AVAudioPCMBuffer)
  public init(buffer: AVFAudio.AVAudioPCMBuffer, bufferStartTime: CoreMedia.CMTime?)
  public let buffer: AVFAudio.AVAudioPCMBuffer
}
```

(`$SDK/System/Library/Frameworks/Speech.framework/Versions/A/Modules/Speech.swiftmodule/arm64e-apple-macos.swiftinterface`,
line 243.) The documentation is explicit that conversion is the caller's job:

> The audio data must have an audio format that is supported by the analyzer's modules; the analyzer
> does not perform audio conversion. Call `bestAvailableAudioFormat(compatibleWith:considering:)` (or
> its variants) to select an appropriate format to convert to.

(<https://developer.apple.com/documentation/speech/analyzerinput>) The same page adds that the format
may change between inputs: "If the new audio format is supported by the modules, the modules will be
reconfigured as needed."

WWDC25 session 277 says the same thing about a non-fixed source, at [16:05]:

> Audio sources have different output formats and sample rates. SpeechTranscriber gave us a
> bestAvailableAudioFormat that we can use. I'm passing our audio buffers through a conversion step to
> ensure that the format matches bestAvailableAudioFormat.

(<https://developer.apple.com/videos/play/wwdc2025/277>)

So the conversion shape is exactly what `Talkify/Dictation/MicrophoneInput.swift` already does with
`AVAudioConverter`, only starting from a different source format. For a tap, the source format is
whatever `kAudioTapPropertyFormat` reports, wrapped in an `AVAudioFormat`. For ScreenCaptureKit it is
the `sampleRate` and `channelCount` you asked for, arriving inside a `CMSampleBuffer` that has to be
unwrapped into an `AVAudioPCMBuffer` first. Expect both a sample-rate change and a channel-count
change: taps and SCK both default to stereo, and `SpeechAnalyzer.bestAvailableAudioFormat` picks the
module's format. `SpeechModule.availableCompatibleAudioFormats` documents two edge cases worth
handling: "If the audio format doesn't matter, then there will be one format listed with a sample rate
of `kAudioStreamAnyRate` and other values 0. If assets are necessary yet not installed on device, then
the list will be empty"
(<https://developer.apple.com/documentation/speech/speechmodule/availablecompatibleaudioformats>).

**Concurrency is capped, and the cap is not a number.** From the `SpeechAnalyzer` page:

> The system normally limits simultaneous analyses to a conservative number, considering hardware
> capabilities of different devices. If you exceed that number, the system throws an
> `insufficientResources` error.

(<https://developer.apple.com/documentation/speech/speechanalyzer>) `SFSpeechError.Code.insufficientResources`
is macOS 26
(<https://developer.apple.com/documentation/speech/sfspeecherror/code/insufficientresources>), so this
applies today. It also means a Live Captions analyzer and Talkify's prewarmed dictation analyzer are
competing for the same budget, and the budget is undocumented.

**Careful with that page: it documents macOS 27 API without separating it.** The overview's sample
code uses `AnalyzerInputConverter`, `CaptureInputSequenceProvider` and `AssetInputSequenceProvider`,
and the escape hatch for the concurrency cap is `SpeechAnalyzer.Options.ignoresResourceLimits`. All
four are macOS 27 beta
(<https://developer.apple.com/documentation/speech/analyzerinputconverter>,
<https://developer.apple.com/documentation/speech/speechanalyzer/options/ignoresresourcelimits>), and
none of them exists in the 26.5 SDK on this machine. Grepping the Speech `.swiftinterface` for each
returns zero hits. On macOS 26 there is no way to raise the concurrency cap, and the conversion helper
has to be written by hand.

Also `SpeechAnalyzer` "can only analyze one input sequence at a time", and finishing is explicit: an
analyzer that is not finished "won't terminate its result streams and will wait for additional audio
input sequences or buffers". Nothing in the documentation caps session duration or states a memory
budget. Unverified for long-running sessions; the only documented lever is
`SpeechAnalyzer.Options.ModelRetention`.

## 4. Known limitations

**One browser tab cannot be isolated. CONTEXT.md is right.** Two independent confirmations.

ScreenCaptureKit is settled by Apple's own words: the audio policy "always works at the app level"
(WWDC22 10155 at [4:13], quoted above). A window filter does not narrow audio, and a tab is not even a
window.

For taps, the unit is an OS process. `kAudioProcessClassID` "contains information about a client
process connected to the HAL" (`AudioHardware.h`), and `CATapDescription` selects by process object or,
on macOS 26, by bundle ID. Enumerating `kAudioHardwarePropertyProcessObjectList` on this machine
returned 35 process objects, including:

```
com.apple.WebKit.GPU
com.brave.Browser
com.brave.Browser.helper
com.brave.Browser.helper
com.google.Chrome
company.thebrowser.dia
company.thebrowser.browser.helper
company.thebrowser.browser.helper
```

Safari-family media playback surfaces as one `com.apple.WebKit.GPU` object for the whole browser.
Chromium browsers surface as a main process plus several helper processes. No object corresponds to a
tab. The domain rule "Browser sources are labeled as capturing all browser audio because capture
cannot isolate one tab" holds for both routes.

One refinement to that rule, marked as inference from the list above rather than from documentation: a
Chromium browser's audio can come from more than one process object, and the helper bundle ID differs
from the application's (`com.brave.Browser.helper` versus `com.brave.Browser`). Capturing "all browser
audio" therefore means tapping a set, not a PID, and the macOS 26 `bundleIDs` plus
`processRestoreEnabled` pair looks aimed at exactly this. Worth measuring before relying on it.

**DRM-protected audio: could not verify.** I found no Apple documentation, header comment or WWDC
statement describing what a process tap or a ScreenCaptureKit audio stream yields for
FairPlay-protected playback. I also searched the SDK for any API letting an application mark its audio
as untappable and found none: `NSWindow.sharingType` excludes a window from screen capture
(`AppKit.framework/Headers/NSWindow.h`, line 522) and has no audio counterpart. Do not assume either
outcome; test with a protected stream before promising anything.

**Creating a tap does not have to mute the source.** `CATapMuteBehavior` defaults to `CATapUnmuted`,
documented as "Audio is captured by the tap and also sent to the audio hardware". The other two values
are deliberate: `CATapMuted` sends no audio to the hardware at all, and `CATapMutedWhenTapped` mutes
"for the duration of the read activity on the tap"
(`CATapDescription.h`; <https://developer.apple.com/documentation/coreaudio/catapmutebehavior>). A tap
left at its default should not silence what the user hears. Whether creating the tap or its aggregate
device causes an audible glitch or a device reconfiguration is not documented either way, and I did not
test it, because creating a tap on this machine would fire the TCC prompt.

**The aggregate device can be kept out of the user's way.** Set `kAudioAggregateDeviceIsPrivateKey`,
and the aggregate is "private to the process that created it" and "not persistent across launches"
(`AudioHardware.h`). Nothing in the documentation says creating a private aggregate changes the
default output device. Unverified but load-bearing enough to test, since a Live Captions session that
switches the user's output device mid-call is a shipping blocker.

**Bluetooth and AirPods.** Nothing route-specific is documented. Two facts are, and they interact.
The device-scoped tap initializers set the tap's format from the chosen device stream: "The format of
the tap will match the format of this stream" (`CATapDescription.h`). AirPods change their output
stream format depending on whether their microphone is also in use. So a device-scoped tap on an
AirPods output inherits whatever that stream currently is, and the tap format can change under you.
The mitigation available from the documentation is to read `kAudioTapPropertyFormat` and to register a
listener rather than caching the format once, and to prefer a mixdown tap when a fixed device is not
required. Untested.

## 5. Prior art

- **Apple, *Capturing system audio with Core Audio taps***,
  <https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps>,
  sample `AudioTapSample`. Proves the full path: `CATapDescription` to `AudioHardwareCreateProcessTap`
  to a private aggregate device to an IOProc, plus the exact `Info.plist` key and the sandbox
  entitlement set that make it work. The page is stamped macOS 26 but its setup instructions say
  macOS 14.2 or later. Its `TapConfig` also shows Apple defaulting `isProcessRestoreEnabled` to true.
- **Apple, *Capturing screen content in macOS***,
  <https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>,
  sample `CaptureSample`. Proves the ScreenCaptureKit audio path: `capturesAudio`,
  `excludesCurrentProcessAudio`, `captureMicrophone`, three `addStreamOutput` calls, and one
  `didOutputSampleBuffer` switch. Also proves it needs Screen Recording plus an app restart, and that
  no capture entitlement is required.
- **Apple, *Bringing advanced speech-to-text capabilities to your app***,
  <https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app>,
  with WWDC25 session 277 <https://developer.apple.com/videos/play/wwdc2025/277>. Proves the
  buffer-to-analyzer path Talkify already uses, including the explicit conversion step to
  `bestAvailableAudioFormat`.
- **insidegui/AudioCap**, <https://github.com/insidegui/AudioCap>. Not first-party, but its README is
  the clearest ordered checklist of the tap sequence, including the detail that the aggregate's tap
  list uses `kAudioSubTapUIDKey` with the tap description's UUID string. It also proves the permission
  gap: "There's no public API to request audio recording permission or to check if the app has that
  permission." Two cautions: it dates the API to macOS 14.4 where the header and Apple's own docs say
  14.2, and its permission check uses private TCC API.
- **No WWDC session covers Core Audio process taps.** Searching 1638 sessions for
  `AudioHardwareCreateProcessTap` and `CATapDescription` returns nothing, and a plain search for
  process-tap audio returns only unrelated hits. The API shipped in a point release with no talk. The
  documentation article and the sample are the whole primary record.

## What this constrains

- **Two permissions, two panes, two stories to tell the user.** A tap asks for System Audio Recording
  and needs `NSAudioCaptureUsageDescription`. ScreenCaptureKit asks for Screen Recording and requires
  the app to be restarted after the grant. For a menu-bar dictation app, asking for screen recording
  to transcribe a meeting is the larger ask, and the restart makes onboarding a two-step flow.
- **The tap route cannot pre-flight its permission with public API.** Any "Live Captions is not
  permitted" state has to be inferred from a failure at capture start, or from private TCC API. That
  rules out a clean pre-check before the HUD opens, unless the design accepts starting capture to find
  out.
- **A private aggregate device is mandatory bookkeeping, not an option.** Create it, keep it private,
  destroy it, and destroy the tap. It is not persistent across launches, so every session rebuilds it,
  and every failure path has to unwind both objects.
- **The tap's audio format is discovered at runtime and can change.** The converter cannot be built
  once at prewarm time from a constant. That is a real difference from `MicrophoneInput`, which reads
  the input node's format once per session.
- **Speech's concurrency budget is shared and undocumented.** A Live Captions analyzer plus Talkify's
  prewarmed dictation analyzer per bound language can hit `insufficientResources`, and on macOS 26
  there is no override. Either the features take turns, or the failure has to be a designed state.
- **Source selection is per application, and for browsers per set of processes.** The picker has to be
  built on `kAudioHardwarePropertyProcessObjectList` (or `SCShareableContent`), and a browser source
  has to gather several process objects. "All browser audio" is not a labeling compromise, it is the
  actual capture unit.
- **Two behaviors have to be measured before any promise is made:** what happens to DRM-protected
  audio, and whether creating a tap or its aggregate disturbs the user's current output device,
  particularly on AirPods. Neither is answerable from Apple's documentation.
- **Display sleep and background sources are unverified.** A meeting-transcription story that assumes
  capture survives a sleeping display is currently unsupported by any primary source.
