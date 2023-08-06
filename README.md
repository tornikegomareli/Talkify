# Talkify: Swift Speech Recognition and Synthesis Library

<p align="center">
<a href="https://swift.org/package-manager/"><img src="https://img.shields.io/badge/SPM-supported-DE5C43.svg?style=for-the-badge"></a>
<a href="https://raw.githubusercontent.com/onevcat/Kingfisher/master/LICENSE"><img src="https://img.shields.io/badge/license-MIT-black.svg?style=for-the-badge"></a>
<img src="https://img.shields.io/badge/mac%20os-000000?style=for-the-badge&logo=macos&logoColor=F0F0F0" />
<img src="https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white" />
</p>

Talkify is a Swift library designed to streamline the process of integrating speech recognition and synthesis capabilities into iOS and macOS applications. The library harnesses the power of native APIs such as SFSpeechRecognizer and AVSpeechSynthesizer, providing a high-level interface that simplifies their usage and handles common tasks, such as managing audio sessions and checking microphone permissions.

The primary component of Talkify is the TalkifySpeechRecognizer class. This class provides a comprehensive set of methods for managing speech recognition tasks. It establishes and manages an AVAudioEngine instance for audio operations, handles speech recognition requests and tasks, and provides delegate methods to keep your application informed about the status of speech recognition processes. It also integrates with TalkifyRecordingSession to facilitate the audio recording process.

## Requirements

- Swift 5.0 or higher
- iOS 13.0 or higher
- macOS 10.15 or higher
- SPM

## Supported Languages

For text to speech and as well for speech to text

| Language                        | Flag           |
|---------------------------------|----------------|
| English (Australia)             | 🇦🇺             |
| English (United Kingdom)        | 🇬🇧             |
| English (United States)         | 🇺🇸             |
| English (Ireland)               | 🇮🇪             |
| English (South Africa)          | 🇿🇦             |
| 中文(中国)                       | 🇨🇳             |
| 中文(香港)                       | 🇭🇰             |
| 中文(台灣)                       | 🇹🇼             |
| Nederlands (België)             | 🇧🇪             |
| Nederlands (Nederland)          | 🇳🇱             |
| Français (Canada)               | 🇨🇦             |
| Français (France)               | 🇫🇷             |
| Deutsch (Deutschland)           | 🇩🇪             |
| Deutsch (Österreich)            | 🇦🇹             |
| Deutsch (Schweiz)               | 🇨🇭             |
| Italiano (Italia)               | 🇮🇹             |
| 日本語 (日本)                    | 🇯🇵             |
| 한국어 (대한민국)                 | 🇰🇷             |
| Norsk (Norge)                   | 🇳🇴             |
| Polski (Polska)                 | 🇵🇱             |
| Português (Brasil)              | 🇧🇷             |
| Português (Portugal)            | 🇵🇹             |
| Română (România)                | 🇷🇴             |
| Русский (Россия)                | 🇷🇺             |
| Slovenčina (Slovenská republika)| 🇸🇰             |
| Español (Argentina)             | 🇦🇷             |
| Español (México)                | 🇲🇽             |
| Español (España)                | 🇪🇸             |
| Español (Estados Unidos)        | 🇺🇸             |
| Svenska (Sverige)               | 🇸🇪             |
| ไทย (ประเทศไทย)               | 🇹🇭             |
| Türkçe (Türkiye)                | 🇹🇷             |

## Supported Voices

| Language             | Voices |
|----------------------|--------|
| Arabic | Maged |
| Bulgarian | Daria |
| Catalan | Montserrat |
| Czech | Zuzana |
| Danish | Sara |
| German | Anna |
| Greek | Melina |
| Australian English | Karen |
| British English | Daniel |
| Irish English | Moira |
| Indian English | Rishi |
| US English | Samantha, Whisper, Princess, Bells, Organ, BadNews, Bubbles, Junior, Bahh, Deranged, Boing, GoodNews, Zarvox, Ralph, Cellos, Kathy, Fred |
| South African English | Tessa, Trinoids, Albert, Hysterical |
| Spanish | Monica (Neutral), Paulina (Mexican) |
| Finnish | Satu |
| French | Amelie (Canadian), Thomas |
| Hebrew | Carmit |
| Hindi | Lekha |
| Croatian | Lana |
| Hungarian | Mariska |
| Indonesian | Damayanti |
| Italian | Alice |
| Japanese | Kyoko |
| Korean | Yuna |
| Malay | Amira |
| Norwegian | Nora |
| Dutch | Ellen (Belgium), Xander (Netherlands) |
| Polish | Zosia |
| Portuguese | Luciana (Brazil), Joana (Portugal) |
| Romanian | Ioana |
| Russian | Milena |
| Slovak | Laura |
| Swedish | Alva |
| Thai | Kanya |
| Turkish | Yelda |
| Ukrainian | Lesya |
| Vietnamese | Linh |
| Chinese | Tingting (China), Sinji (Hong Kong), Meijia (Taiwan) |


## Features

- [x] Text to Speech on different languages with different type of voice models.
- [x] Listens to your voice and provides text, based on your setup.
- [x] You can get all available list of voices programatically
- [x] With Ergonomics while using
- [x] Dedicated delegates to control recording/speaking/reading states on your side.
- [ ] RxSwift, Combine, TCA Support

## Installation

Talkify is available through the [Swift Package Manager](https://swift.org/package-manager/). 

## Swift Package Manager

To integrate Talkify into your project using SPM, you can add the package dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/tornikegomareli/Talkify.git", .upToNextMajor(from: "0.1.0"))
]
```

## Prerequisites

Before you start using Talkify, there are a few setup steps you need to ensure:

### 1. Permissions in Info.plist

To use the recording features of Talkify, you need to request microphone access. Additionally, for speech recognition, you must request speech recognition authorization. Add the following keys to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to the microphone to record your voice.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>We need access to speech recognition to convert your voice into text.</string>
```

### 2. Enabling Audio Input (macOS Only)
For macOS users:

Open your Xcode project.
Navigate to the "Signing & Capabilities" tab.
In the "Resource Access" section, ensure that "Audio Input" is selected. This allows recording of audio using the built-in microphone and grants access to audio inputs using any Core Audio API that supports audio input. This step is not required for iOS.

## How to Use

The `Talkify` class provides a high-level API for managing speech synthesis, recognition tasks and reading text with different voices. 

Here's a guide on how to use it:

### 1. Setup

To start with, you'll need to initialize a `Talkify` instance:

```swift
let talkify = Talkify()
```

Setup delegates

```swift
talkify.recordingDelegate = self
talkify.speakingDelegate = self
```

Your class should then conform to the `TalkifyRecordingDelegate` and `TalkifySpeakingDelegate` protocols and implement their respective methods.

### 2. Recording Voice 
Before starting recording, ensure to set up the recorder:

```swift
talkify
  .setupRecording()
  .startRecording()
```

You can stop recording programatically with 

```swift
talkify
  .stopRecording()
```
The recognized text will be available through the `recordingDidFinishWithResults(text:)` delegate method.

### 3. Speech Synthesis
To start speaking a text, you need to setup speaker

Initialize the `TalkifySpeaker`:

```swift
let speaker = TalkifySpeaker()
```

Customizing Voice:

```swift
speaker.withVoice(customVoice: .kyoko) // Sets the voice to Kyoko (Japanese Female voice)
```

Customizing Voice Rate:
This adjusts the speed at which the text is spoken. The value range typically is between 0.0 (slowest) and 1.0 (fastest), with 0.5 being the default rate.

```swift
speaker.withVoiceRate(value: 0.7) // Sets a faster speaking rate
```

Customizing Pitch Multiplier:
This adjusts the pitch of the synthesized voice. A value of 1.0 means a regular pitch. Values above or below this can be used to raise or lower the pitch, respectively.

```swift
speaker.withMultiplier(value: 1.2) // Raises the pitch slightly
```

Customizing Volume:
This adjusts the volume of the synthesized voice, with 1.0 being the loudest and 0.0 being muted.

```swift
speaker.withVolume(value: 0.8) // Slightly quieter than the default volume
```

Set speaker to Talkify instance:

```swift
talkify.setSpaker(wih: speaker) // Pass above created speaker instance
```

Start Speaking:

```swift
talkify.speak(text: "Hello, this is Talkify!")
```

You can pause or continue the speech synthesis using:

```swift
talkify.pauseSpeaking()
talkify.continueSpeaking()
```

Remember to handle the delegate methods for `TalkifySpeakingDelegate` to get callbacks about the speech synthesis status.

### 4. Setting a Specific Voice for Synthesis

With Talkify, you can choose a particular voice for speech synthesis. Here's how to set a voice:

```swift
let voice = TalkifyVoice(voice: .samantha, quality: .default)
talkify.voice = voice
```
 
Replace .samantha with the desired voice identifier from the `TalkifyVoiceIdentifier` enum. The quality parameter lets you set the voice's quality; you can choose between `.default` and other available options.

### 5. Choosing a Language for Recognition and Synthesis

To set a specific language for speech recognition and synthesis, you can leverage the `TalkifyLanguage` enum:

```swift
let language: TalkifyLanguage = .englishUS
talkify.recognitionLanguage = language
talkify.synthesisLanguage = language
```

Replace `.englishUS` with your desired language option from the `TalkifyLanguage` enum.
---
For detailed usage and advanced functionalities, refer to the inline documentation provided within the Talkify class and its extensions.

# Why ?
Just to beat my procrastination 😄

But it really aims to be a comprehensive solution for developers looking to incorporate speech recognition and synthesis into their apps. It abstracts away the complexity of the underlying APIs, allowing developers to focus on creating engaging user experiences.

## Contribution 🤝

I will appreciate your contributions! Whether you're fixing bugs, improving the documentation, or enhancing the features, I'd love to have your help. Here's how you can contribute:

1. **Fork the repository**: Start by forking the [Talkify repository](https://github.com/tornikegomareli/Talkify/tree/main).
2. **Clone your fork**: `git clone https://github.com/YOUR_USERNAME/Talkify.git`
3. **Create a branch**: `git checkout -b your-branch-name`
4. **Make your changes**: Improve the codebase, add features, fix bugs, or enhance the documentation.
5. **Commit your changes**: `git commit -m "Your descriptive commit message"`
6. **Push to your fork**: `git push origin your-branch-name`
7. **Submit a pull request**: Go to the Talkify repository and create a new pull request. Describe your changes in detail and ensure it's directed from your branch to the main Talkify branch.

## Issues 🐞

Encountered a bug or an unexpected behavior? I appreciate your feedback. Please open a new issue on the [GitHub repository](https://github.com/tornikegomareli/Talkify/tree/main/issues), providing as much detail as possible. This helps us address and fix issues faster.

## Future Plans ⚒️

Because this repository is more for educational purpose, I will happily add new functionalities step by step

- **watchOS Support**: Aim to extend Talkify's capabilities to watchOS, allowing for seamless integration with Apple Watch applications.
- **Rx and Combine Listeners**: In addition to the delegate pattern, I'm planning on introducing listeners using popular reactive frameworks like RxSwift and Combine.
- **Unit Tests**: To ensure the robustness and reliability of Talkify, unit tests are on the way. This will boost confidence in the library's functionality and make future changes safer.
- **Third party integrations**: I have idea to add some third party APIS, for example ChatGPT Speech recognition api with ergonomics to use, but I don't know I need to still think about it, if it will be worth at all.

---

---

## 🌟

If you've found the README helpful or you like the project idea, please give it a ⭐️ (star) on GitHub. 

