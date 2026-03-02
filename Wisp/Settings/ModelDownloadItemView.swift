import SwiftUI

struct ModelDownloadItemView: View {
    let name: String
    let sizeString: String
    let description: String
    let isDownloaded: Bool
    let downloadProgress: Double
    let isDownloading: Bool
    let isDownloadingThisModel: Bool
    let onDownload: () async throws -> Void
    let onCancel: () -> Void

    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("(\(sizeString))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if downloadProgress > 0 && downloadProgress < 1 {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 4)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if isDownloadingThisModel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .imageScale(.large)
            } else {
                Button(action: {
                    Task {
                        do {
                            try await onDownload()
                        } catch is CancellationError {
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDownloading)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}
