<p align="center">
<img src="docs/app-icon.png" width="128" />
</p>

# Wisp

Wisp is a macOS application that provides real-time audio transcription using the Whisper model. It offers a seamless way to record and transcribe audio with customizable settings and keyboard shortcuts.

> Wisp is a friendly fork of [OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) by [@Starmel](https://github.com/Starmel) — renamed for brevity, with added Ukrainian language support and a fresh icon.

<p align="center">
<img src="docs/image.png" width="400" /> <img src="docs/image_indicator.png" width="400" />
</p>

## Features

- Real-time audio recording and transcription
- Two transcription engines: [Whisper](https://github.com/ggerganov/whisper.cpp) and [Parakeet](https://github.com/AntinomyCollective/FluidAudio) — download models directly from the app
- Global keyboard shortcuts — key combination or single modifier key (e.g. Left Cmd, Right Option, Fn)
- Hold-to-record mode — hold the shortcut to record, release to stop
- Drag & drop audio files for transcription with queue processing
- Microphone selection — switch between built-in, external, Bluetooth and iPhone (Apple Continuity) mics from the menu bar
- Support for multiple languages with auto-detection
- Asian language autocorrect ([autocorrect](https://github.com/huacnlee/autocorrect))

## Installation

```shell
brew tap andrii-rubtsov/tap
brew install --cask wisp
```

Or download the DMG from the [Releases page](https://github.com/andrii-rubtsov/Wisp/releases).

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (ARM64)

## Building locally

```shell
git clone git@github.com:andrii-rubtsov/Wisp.git
cd OpenSuperWhisper
git submodule update --init --recursive
brew install cmake libomp rust ruby
gem install xcpretty
./run.sh build
```

In case of problems, consult `.github/workflows/build.yml` which is our CI workflow
where the app gets built automatically on GitHub's CI.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or create issues for bugs and feature requests.

## License

Wisp is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
