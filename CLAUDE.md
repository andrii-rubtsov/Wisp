# Wisp

macOS menu-bar app for speech-to-text using Whisper.cpp and FluidAudio (Parakeet) engines.

## Build

```bash
xcodebuild -scheme Wisp -configuration Debug -derivedDataPath build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO build
```

## Test

Run unit tests before every commit or handoff:

```bash
xcodebuild test -scheme Wisp -configuration Debug -derivedDataPath build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO -only-testing:WispTests 2>&1 | tail -20
```

Skip UI tests (they require accessibility permissions and a running GUI session).

## Architecture

- **Engines**: `WhisperEngine` (whisper.cpp C bridge) and `FluidAudioEngine` (Parakeet SDK). Both conform to `TranscriptionEngine` protocol.
- **ShortcutBinding**: Each binding carries its own engine, model, and initial prompt. Key combos only (modifier + key). Stored as JSON in UserDefaults (`shortcutBindingsV3`).
- **AppPreferences**: Single source of truth for all settings (UserDefaults wrapper). Engines read from it directly — no intermediate `Settings` struct.
- **IndicatorWindow**: Floating `NSPanel` showing recording/transcription state.
- **TranscriptionFilter**: Filters hallucinated outputs from silence (e.g., "Thank you", "Продолжение следует").

## Conventions

- Swift 5, macOS 14+ deployment target
- `@MainActor` for all UI/ObservableObject classes
- Prefer `let` over `var`, value types over reference types
- No force unwraps in new code — use `guard let` or `if let`
- New test files go in `WispTests/`
- Do not modify `.pbxproj` manually — Xcode manages it via file system synchronization
- Always update `README.md` before creating a commit or pushing
