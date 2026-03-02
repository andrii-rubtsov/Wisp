import SwiftUI

struct RecordingRow: View {
    let recording: Recording
    let searchQuery: String
    let onDelete: () -> Void
    let onRegenerate: () -> Void
    @StateObject private var audioRecorder = AudioRecorder.shared
    @State private var showTranscription = false
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isPlaying: Bool {
        audioRecorder.isPlaying && audioRecorder.currentlyPlayingURL == recording.url
    }

    private var isPending: Bool {
        recording.status == .pending || recording.status == .converting || recording.status == .transcribing
    }

    private var isRegenerating: Bool {
        recording.isRegeneration && isPending
    }

    private var statusText: String {
        switch recording.status {
        case .pending:
            return "In queue..."
        case .converting:
            return "Converting..."
        case .transcribing:
            return "Transcribing..."
        case .completed:
            return ""
        case .failed:
            return "Failed"
        }
    }

    private var displayText: String {
        if recording.transcription.isEmpty || recording.transcription == "Starting transcription..." || recording.transcription == "In queue..." {
            return ""
        }
        return recording.transcription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isPending && !isRegenerating {
                VStack(alignment: .leading, spacing: 4) {
                    if let sourceFileName = recording.sourceFileName {
                        Text(sourceFileName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 6) {
                        if recording.status == .pending {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ProgressCircle(progress: recording.progress)
                        }

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if recording.status == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("Transcription failed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if !recording.transcription.isEmpty {
                        Text(recording.transcription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, isPending && !isRegenerating ? 4 : 8)
            } else if !displayText.isEmpty {
                ZStack(alignment: .topLeading) {
                    TranscriptionView(
                        transcribedText: displayText,
                        searchQuery: searchQuery,
                        isExpanded: $showTranscription
                    )

                    if isRegenerating {
                        ShimmerOverlay()
                            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, isPending && !isRegenerating ? 4 : 8)
            } else if !isPending {
                Text("No speech detected")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.timestamp, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(recording.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if isRegenerating {
                    Spacer()
                        .frame(width: 2)
                    HStack(spacing: 6) {
                        if recording.status == .pending {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ProgressCircle(progress: recording.progress)
                        }

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                }

                Spacer()

                HStack(spacing: 16) {
                    if !isPending && recording.status != .failed && (isHovered || isPlaying) {
                        Button(action: {
                            if isPlaying {
                                audioRecorder.stopPlaying()
                            } else {
                                audioRecorder.playRecording(url: recording.url)
                            }
                        }) {
                            Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(isPlaying ? .red : ThemePalette.iconAccent(colorScheme))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                recording.transcription, forType: .string
                            )
                        }) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy entire text")
                        .transition(.opacity)
                    }

                    if (recording.status == .completed || recording.status == .failed) && isHovered {
                        Button(action: {
                            onRegenerate()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate transcription")
                        .transition(.opacity)
                    }

                    if isHovered || isPlaying || (isPending && !isRegenerating) || recording.status == .failed {
                        Button(action: {
                            if isPlaying {
                                audioRecorder.stopPlaying()
                            }
                            onDelete()
                        }) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
                .animation(.easeInOut(duration: 0.2), value: isRegenerating)
            }
            .animation(.easeInOut(duration: 0.2), value: isRegenerating)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(ThemePalette.cardBackground(colorScheme))
        }
        .background(ThemePalette.cardBackground(colorScheme))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ThemePalette.cardBorder(colorScheme), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(.vertical, 4)
    }
}

private struct ProgressCircle: View {
    let progress: Float

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 2)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
        }
        .frame(width: 16, height: 16)

        Text("\(Int(progress * 100))%")
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.1), value: progress)
    }
}
