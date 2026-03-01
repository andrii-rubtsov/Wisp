# Wisp Codebase Analysis & Suggestions

## App Size Reduction

| Opportunity | Savings | Effort |
|---|---|---|
| Enable LTO in Release (`LLVM_LTO = YES`) for all targets | 1-2 MB | 1 min |
| Remove `jfk.wav` test file from release target | 344 KB | 1 min |
| Eliminate `libomp.dylib` (whisper.cpp can use Apple Accelerate instead) | 722 KB | Medium |
| Offer quantized whisper models (`ggml-tiny-q5`) | 40-50 MB less download | Low |
| Replace `KeyboardShortcuts` SPM with native `CGEvent`/`NSEvent` APIs | ~100 KB | Medium |

LTO is the easiest win - already enabled on Release app target, but static whisper libraries (`libwhisper.a` 6.8 MB, `libggml-*.a` ~10 MB) could benefit from whole-module LTO.

---

## Code Inconsistencies

### 1. Three-layer Settings duplication (biggest smell)

`AppPreferences` (UserDefaults wrapper) -> `SettingsViewModel` (22 `@Published` + `didSet` sync) -> `Settings` struct (stale copy for engines).

Every preference change goes through 3 layers manually. The `Settings` struct is created fresh each transcription and could just read `AppPreferences` directly.

### 2. Two engines, inconsistent patterns

- `WhisperEngine`: 500 lines, manual NSLock, unsafe pointers, custom PCM conversion
- `FluidAudioEngine`: 110 lines, modern async/await, SDK-managed
- `onProgressUpdate` callback exists in both but isn't part of the `TranscriptionEngine` protocol

### 3. Clipboard paste uses hardcoded 100ms sleep

`ClipboardUtil.swift`: saves pasteboard, sets text, simulates Cmd+V, sleeps 100ms, restores original clipboard. If the target app is slow, restoration happens too early and paste fails silently.

---

## Performance

### 1. Large audio files load entirely into memory

`WhisperEngine.convertAudioToPCM` pre-allocates the full output buffer: `[Float](repeating: 0, count: outputFrameCount)`. For a 2-hour recording this could be hundreds of MB. Should use chunked/streaming conversion.

### 2. Manual NSLock in WhisperEngine

`isCancelled` and `isTranscribing` use manual lock/unlock pattern. Modern Swift actors would be cleaner and eliminate the race window in `TranscriptionQueue.cancelRecording()`.

### 3. Audio connection monitoring polls file size

`AudioRecorder` uses a `DispatchSource` timer to poll file size every second to detect if audio is flowing. Could use `AVAudioRecorder` delegate callbacks instead.

---

## Error Handling Gaps

- `FluidAudioEngine` line ~66: `catch { // Stream finished or error }` — silently swallows all stream errors
- `WhisperEngine` line ~433: prints conversion error then `break` — error lost, not surfaced to user
- `TranscriptionError` enum has no associated values — no underlying error context for debugging

---

## Quick Wins

1. **Enable LTO** on Release for all targets — free size win
2. **Remove `jfk.wav`** from release build target membership
3. **Collapse Settings layers** — delete the `Settings` struct, have engines read `AppPreferences` directly
4. **Add `onProgressUpdate` to `TranscriptionEngine` protocol** — both engines already have it
5. **Replace fixed clipboard delay** with shorter sleep (50ms) or event-based check
6. **Remove deprecated `insertTextUsingPasteboard`** in ClipboardUtil.swift — marked deprecated, just forwards to `insertText`

---

## Dead Code

- `ClipboardUtil.swift`: deprecated `insertTextUsingPasteboard` method (just forwards to `insertText`)
- `WhisperDownloadDelegate.swift`: empty `didResumeAtOffset` delegate method
- `WhisperDownloadDelegate.swift`: empty `else` block in `didCompleteWithError`
- `Settings.swift`: `asianLanguages` constant was removed (2025-03)
