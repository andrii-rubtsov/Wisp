import KeyboardShortcuts
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    @State private var previousModelURL: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            shortcutSettings
                .tabItem {
                    Label("Shortcuts and models", systemImage: "command")
                }
                .tag(0)

            modelDownloadsTab
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .tag(1)

            transcriptionSettings
                .tabItem {
                    Label("Transcription", systemImage: "text.bubble")
                }
                .tag(2)

            advancedSettings
                .tabItem {
                    Label("Advanced", systemImage: "gear")
                }
                .tag(3)
        }
        .padding()
        .frame(minWidth: 650, maxWidth: .infinity)
        .background(Color(.windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Spacer()

                Link(destination: URL(string: "https://github.com/andrii-rubtsov/Wisp")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 10))
                        Text("GitHub")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .onAppear {
            previousModelURL = viewModel.selectedModelURL
            viewModel.initializeFluidAudioModels()
            viewModel.initializeDownloadableModels()
        }
    }

    // MARK: - Shortcuts Tab

    private var shortcutSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Shortcuts for models
                VStack(alignment: .leading, spacing: 16) {
                    Text("Shortcuts for models")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(spacing: 8) {
                        ForEach($viewModel.shortcutBindings) { $binding in
                            ShortcutBindingRow(
                                binding: $binding,
                                modelChoices: viewModel.availableModelChoices(for: binding.engine),
                                canDelete: viewModel.shortcutBindings.count > 1,
                                onDelete: { viewModel.removeShortcutBinding(id: binding.id) },
                                viewModel: viewModel
                            )
                        }

                        if viewModel.shortcutBindings.count < ShortcutBinding.maxBindings {
                            Button(action: { viewModel.addShortcutBinding() }) {
                                Label("Add shortcut for model", systemImage: "plus")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 4)
                        }
                    }

                    Text("Each shortcut triggers recording with its assigned engine, model, and initial prompt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Recording Behavior
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Behavior")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Text("Play sound when recording starts")
                            .font(.subheadline)
                        Spacer()
                        Toggle("", isOn: $viewModel.playSoundOnRecordStart)
                            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                            .labelsHidden()
                            .help("Play a notification sound when recording begins")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Recording Indicator Position
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Indicator")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Text("Position")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $viewModel.indicatorPosition) {
                            ForEach(IndicatorPosition.allCases) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    // MARK: - Model Downloads Tab

    private var modelDownloadsTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                modelDownloadSection
            }
            .padding()
        }
    }

    private var modelDownloadSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Downloads")
                .font(.headline)
                .foregroundColor(.primary)

            // Whisper Models
            VStack(alignment: .leading, spacing: 8) {
                Text("Whisper Models")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(spacing: 8) {
                    ForEach($viewModel.downloadableModels) { $model in
                        ModelDownloadItemView(
                            name: model.name,
                            sizeString: model.sizeString,
                            description: model.description,
                            isDownloaded: model.isDownloaded,
                            downloadProgress: model.downloadProgress,
                            isDownloading: viewModel.isDownloading,
                            isDownloadingThisModel: viewModel.isDownloading && viewModel.downloadingModelName == model.name,
                            onDownload: { try await viewModel.downloadModel(model) },
                            onCancel: { viewModel.cancelDownload() }
                        )
                    }
                }
            }

            Divider()

            // Parakeet Models
            VStack(alignment: .leading, spacing: 8) {
                Text("Parakeet Models")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(spacing: 8) {
                    ForEach($viewModel.downloadableFluidAudioModels) { $model in
                        ModelDownloadItemView(
                            name: model.name,
                            sizeString: model.sizeString,
                            description: model.description,
                            isDownloaded: model.isDownloaded,
                            downloadProgress: model.downloadProgress,
                            isDownloading: viewModel.isDownloading,
                            isDownloadingThisModel: viewModel.isDownloading && viewModel.downloadingModelName == model.name,
                            onDownload: { try await viewModel.downloadFluidAudioModel(model) },
                            onCancel: { viewModel.cancelDownload() }
                        )
                    }
                }
            }

            // Download progress
            if viewModel.isDownloading {
                VStack(spacing: 8) {
                    HStack {
                        if viewModel.downloadProgress > 0 {
                            ProgressView(value: viewModel.downloadProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }

                        Spacer()

                        Button("Cancel") {
                            viewModel.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let downloadingName = viewModel.downloadingModelName {
                        Text("Downloading: \(downloadingName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    // MARK: - Transcription Tab

    private var transcriptionSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Language Settings")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcription Language")
                            .font(.subheadline)

                        Picker("Language", selection: $viewModel.selectedLanguage) {
                            ForEach(LanguageUtil.availableLanguages, id: \.self) { code in
                                Text(LanguageUtil.languageNames[code] ?? code)
                                    .tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Text("Translate to English")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.translateToEnglish)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Output Options")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Show Timestamps")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.showTimestamps)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }

                        HStack {
                            Text("Suppress Blank Audio")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.suppressBlankAudio)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Transcriptions Directory")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Directory:")
                                .font(.subheadline)
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(Recording.recordingsDirectory)
                            }) {
                                Label("Open Folder", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .help("Open transcriptions directory")
                        }

                        Text(Recording.recordingsDirectory.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    // MARK: - Advanced Tab

    private var advancedSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Decoding Strategy")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Whisper only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Use Beam Search")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.useBeamSearch)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                                .help("Beam search can provide better results but is slower")
                        }

                        if viewModel.useBeamSearch {
                            HStack {
                                Text("Beam Size:")
                                    .font(.subheadline)
                                Spacer()
                                Stepper("\(viewModel.beamSize)", value: $viewModel.beamSize, in: 1...10)
                                    .help("Number of beams to use in beam search")
                                    .frame(width: 120)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Model Parameters")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Whisper only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Temperature:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.temperature))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: $viewModel.temperature, in: 0.0...1.0, step: 0.1)
                                .help("Higher values make the output more random")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("No Speech Threshold:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.noSpeechThreshold))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: $viewModel.noSpeechThreshold, in: 0.0...1.0, step: 0.1)
                                .help("Threshold for detecting speech vs. silence")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Debug Options")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Text("Debug Mode")
                            .font(.subheadline)
                        Spacer()
                        Toggle("", isOn: $viewModel.debugMode)
                            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                            .labelsHidden()
                            .help("Enable additional logging and debugging information")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}
