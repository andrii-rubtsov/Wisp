import KeyboardShortcuts
import SwiftUI

struct ShortcutBindingRow: View {
    @Binding var binding: ShortcutBinding
    let modelChoices: [(id: String, name: String, downloaded: Bool)]
    let canDelete: Bool
    let onDelete: () -> Void
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""

    private var isModelDownloaded: Bool {
        modelChoices.first(where: { $0.id == binding.modelIdentifier })?.downloaded ?? false
    }

    private var modelSizeString: String? {
        if binding.engine == "whisper" {
            return SettingsDownloadableModels.availableModels.first(where: { $0.url.lastPathComponent == binding.modelIdentifier })?.sizeString
        } else {
            return SettingsFluidAudioModels.availableModels.first(where: { $0.version == binding.modelIdentifier })?.sizeString
        }
    }

    private var modelDescription: String? {
        if binding.engine == "whisper" {
            return SettingsDownloadableModels.availableModels.first(where: { $0.url.lastPathComponent == binding.modelIdentifier })?.description
        } else {
            return SettingsFluidAudioModels.availableModels.first(where: { $0.version == binding.modelIdentifier })?.description
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                KeyboardShortcuts.Recorder("", name: binding.keyboardShortcutsName)
                    .frame(width: 150)

                Picker("", selection: $binding.engine) {
                    Text("Whisper").tag("whisper")
                    Text("Parakeet").tag("fluidaudio")
                }
                .pickerStyle(.menu)
                .frame(width: 90)
                .onChange(of: binding.engine) { _, newEngine in
                    let choices = newEngine == "fluidaudio"
                        ? SettingsFluidAudioModels.availableModels.map { (id: $0.version, name: $0.name) }
                        : SettingsDownloadableModels.availableModels.map { (id: $0.url.lastPathComponent, name: $0.name) }
                    if let first = choices.first {
                        binding.modelIdentifier = first.id
                        binding.modelDisplayName = first.name
                    }
                }

                Picker("", selection: $binding.modelIdentifier) {
                    ForEach(modelChoices, id: \.id) { choice in
                        HStack {
                            Text(choice.name)
                            if !choice.downloaded {
                                Text("(not downloaded)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(choice.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 120)
                .onChange(of: binding.modelIdentifier) { _, newId in
                    if let match = modelChoices.first(where: { $0.id == newId }) {
                        binding.modelDisplayName = match.name
                    }
                }

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(canDelete ? .secondary : .secondary.opacity(0.3))
                }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
            }

            // Model status
            if !isModelDownloaded {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(binding.modelDisplayName) is not downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let size = modelSizeString, let desc = modelDescription {
                            Text("\(desc) — \(size)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }

                    Spacer()

                    if viewModel.isDownloading && viewModel.downloadingModelName == binding.modelDisplayName {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.6)
                        Button("Cancel") {
                            viewModel.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    } else {
                        Button(action: {
                            Task {
                                do {
                                    if binding.engine == "whisper" {
                                        if let model = viewModel.downloadableModels.first(where: { $0.url.lastPathComponent == binding.modelIdentifier }) {
                                            try await viewModel.downloadModel(model)
                                        }
                                    } else {
                                        if let model = viewModel.downloadableFluidAudioModels.first(where: { $0.version == binding.modelIdentifier }) {
                                            try await viewModel.downloadFluidAudioModel(model)
                                        }
                                    }
                                } catch is CancellationError {
                                } catch {
                                    errorMessage = error.localizedDescription
                                    showError = true
                                }
                            }
                        }) {
                            Label("Download", systemImage: "arrow.down.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(viewModel.isDownloading)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(binding.modelDisplayName) ready")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let size = modelSizeString {
                        Text("(\(size))")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            // Initial prompt
            if binding.engine == "whisper" {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Initial Prompt:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextEditor(text: $binding.initialPrompt)
                        .font(.system(size: 13))
                        .frame(height: 70)
                        .padding(4)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    Text("Not a system prompt. Provide a sample of expected output text to guide style, spelling, and formatting (e.g. proper nouns, punctuation, casing).")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.top, 2)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Initial Prompt is not supported by Parakeet.")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}
