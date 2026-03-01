# Task: Integrate NVIDIA Canary 1B v2 ASR Model into Wisp

## Context

Wisp (https://github.com/andrii-rubtsov/Wisp) is a macOS dictation/transcription app forked from OpenSuperWhisper. It currently supports two speech recognition engines:

1. **Whisper** — via whisper.cpp (C library, bridged to Swift)
2. **Parakeet TDT 0.6B v3** — via CoreML (NVIDIA's model converted to CoreML format using FluidAudio/AntinomyCollective)

The goal is to add a **third engine**: **NVIDIA Canary 1B v2** — a more accurate multilingual ASR model.

## Why Canary

| Model | WER (English) | RTFx (speed) | Languages | Params |
|-------|--------------|-------------|-----------|--------|
| Parakeet TDT 0.6B v3 | ~6.0% | 3300+ | 25 | 600M |
| **Canary 1B v2** | **~6.3%** | **749** | **25** | **1B** |
| Whisper Large V3 Turbo | ~7.2% | 216 | 99+ | 809M |
| Whisper Large V3 | ~7.4% | 69 | 99+ | 1.55B |

Canary 1B v2 is more accurate than Whisper and nearly as fast as Parakeet. It supports 25 European languages including Russian and Ukrainian. It would give Wisp users a "best accuracy" option alongside Parakeet's "best speed" option.

---

## Analysis Results (2026-03-01)

### Step 1: Current Architecture

The engine architecture is clean and plugin-friendly.

**TranscriptionEngine protocol** (`OpenSuperWhisper/Engines/TranscriptionEngine.swift`):
```swift
protocol TranscriptionEngine: AnyObject {
    var isModelLoaded: Bool { get }
    var engineName: String { get }
    func initialize() async throws
    func transcribeAudio(url: URL, settings: Settings) async throws -> String
    func cancelTranscription()
    func getSupportedLanguages() -> [String]
}
```

**Engine selection** is string-based in `AppPreferences.selectedEngine` (`"whisper"` or `"fluidaudio"`). Adding `"canary"` requires:
1. New `CanaryEngine` class conforming to `TranscriptionEngine`
2. One extra branch in `TranscriptionService.loadEngine()`
3. Third option in the Settings UI segmented picker

**WhisperEngine** (~500 lines): Wraps whisper.cpp C library. Handles PCM conversion (parallel multi-core), C callback progress, unsafe pointer cancellation. Models are `.bin` files in `~/Library/Application Support/[BundleID]/whisper-models/`.

**FluidAudioEngine** (~110 lines): Wraps FluidAudio SDK. Much simpler — `AsrModels.downloadAndLoad(version:)` handles everything. Progress via async stream. Models cached by the SDK internally.

**Key architectural notes:**
- `onProgressUpdate` callback exists in both engines but is NOT in the protocol (accessed via type casting in TranscriptionService) — should be added to protocol
- Settings struct is passed to engines but FluidAudioEngine ignores most of it (language, beam search, etc. are Whisper-specific)
- Model management differs per engine: WhisperModelManager for Whisper, FluidAudio SDK handles its own for Parakeet

### Step 2: Canary CoreML/ONNX Feasibility

**Core problem**: Parakeet uses a non-autoregressive TDT decoder (simple, fast to convert). Canary uses a **full Transformer decoder** that generates tokens one-by-one like an LLM — fundamentally harder to run on Apple Neural Engine.

| Path | Feasible? | Effort | Status |
|------|-----------|--------|--------|
| **FluidAudio SDK** | NO | N/A | Only supports Parakeet models. Aware of Canary but no support shipped. |
| **CoreML (Apple Neural Engine)** | Theoretically yes | Very High | **Nobody has done it.** FluidInference converted Parakeet's FastConformer encoder (same as Canary's) but the autoregressive Transformer decoder requires KV-cache management that CoreML doesn't handle well. |
| **ONNX Runtime (Python)** | **YES — working today** | Low | `onnx-asr` Python package with pre-converted INT8 models (~1 GB). Supports CoreML execution provider on Apple Silicon. |
| **ONNX Runtime (native Swift/C)** | Feasible | Medium-High | Use existing ONNX models + ONNX Runtime C API. Must implement mel-spectrogram preprocessing and autoregressive decode loop in Swift/C++. |
| **Sherpa-ONNX** | Partial | High | Not officially supported ([Issue #1767](https://github.com/k2-fsa/sherpa-onnx/issues/1767)). `EncDecMultiTaskModel` architecture not recognized. Community workarounds are fragile. |

**Pre-converted ONNX models exist**: [istupakov/canary-1b-v2-onnx](https://huggingface.co/istupakov/canary-1b-v2-onnx)

| File | Size |
|------|------|
| `encoder-model.onnx` + `.data` | ~3.28 GB |
| `encoder-model.int8.onnx` | 859 MB |
| `decoder-model.onnx` | 676 MB |
| `decoder-model.int8.onnx` | 170 MB |
| **INT8 total** | **~1 GB** |

### Step 3: Recommendation

**Best option: Wait for FluidAudio/FluidInference to add Canary support.**

They already converted Parakeet's FastConformer encoder to CoreML (same encoder Canary uses). They are aware of Canary. When they ship it, integrating into Wisp would take a day — same `AsrModels.downloadAndLoad()` pattern as FluidAudioEngine.

**If you want it now: ONNX Runtime C API path.**

1. Use INT8 quantized models from `istupakov/canary-1b-v2-onnx` (~1 GB download)
2. Add ONNX Runtime as a dependency (C API with Swift-compatible headers)
3. Implement mel-spectrogram preprocessing in Swift/C++
4. Implement autoregressive decode loop with KV-cache management
5. Wrap in `CanaryEngine` conforming to `TranscriptionEngine` protocol
6. Add to Settings UI as third engine option

**Estimated effort**: 2-4 weeks for a working integration, significant complexity in the decode loop.

**Not recommended**: CoreML conversion from scratch (nobody has done it, the autoregressive decoder is the main blocker), Python subprocess bridge (adds ~500 MB Python runtime dependency, defeats the purpose of a native app).

---

## Key Resources

- **Canary 1B v2 model**: https://huggingface.co/nvidia/canary-1b-v2
- **Canary ONNX models**: https://huggingface.co/istupakov/canary-1b-v2-onnx
- **onnx-asr Python package**: https://pypi.org/project/onnx-asr/
- **Canary paper**: https://arxiv.org/html/2509.14128v1
- **Parakeet v3 model**: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- **FluidAudio (Parakeet CoreML)**: https://github.com/AntinomyCollective/FluidAudio
- **FluidInference Parakeet CoreML models**: https://huggingface.co/FluidInference
- **NVIDIA NeMo**: https://github.com/NVIDIA/NeMo (Canary's native framework)
- **Sherpa-ONNX Canary issue**: https://github.com/k2-fsa/sherpa-onnx/issues/1767
- **Open ASR Leaderboard**: https://huggingface.co/spaces/hf-audio/open_asr_leaderboard

## Constraints

- Must run locally on Apple Silicon (M1/M2/M3/M4)
- No cloud API calls — everything offline
- Must integrate with existing Wisp UI patterns (engine selector, model downloader)
- macOS 14.0+ (Sonoma)
- Swift / SwiftUI codebase
