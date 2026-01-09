import SwiftUI
import os.log

@available(iOS 26.0, *)
struct ContentView: View {
    @StateObject private var recorder = RealtimeTranscriptionRecorder()
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var currentMemoId: UUID?
    @Environment(\.dismiss) private var dismiss

    private let voiceMemoController = VoiceMemoController.shared
    private let fileManagerClient = FileManagerClient.live

    var body: some View {
        VStack(spacing: 20) {
            RealtimeTranscriptionResultView(recorder: recorder)
            RealtimeRecordingTimeView(recorder: recorder)
            RealtimeRecordingButtonView(
                recorder: recorder,
                onRecordingComplete: { memoId, audioFileURL, transcription in
                    await saveRecording(memoId: memoId, audioFileURL: audioFileURL, transcription: transcription)
                },
                onDismiss: { dismiss() },
                currentMemoId: $currentMemoId
            )
            Spacer()
        }
        .padding()
        .navigationTitle("音声録音")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .disabled(recorder.isRecording)
            }
        }
        .navigationBarBackButtonHidden(recorder.isRecording)
        .sheet(isPresented: $showingSettings) {
            RealtimeSettingsView()
        }
    }

    private func saveRecording(memoId: UUID, audioFileURL: URL, transcription: String) async {
        AppLogger.ui.debug("saveRecording called")
        AppLogger.fileOperation.info("Audio file URL: \(audioFileURL.path)")
        AppLogger.ui.info("Memo ID: \(memoId.uuidString)")
        AppLogger.speechRecognition.info("Transcription: \(transcription.prefix(50))...")

        do {
            // Move file to proper location
            _ = try await fileManagerClient.moveFile(audioFileURL, memoId, .recording)

            // Save memo with transcription
            await MainActor.run {
                voiceMemoController.saveVoiceMemo(
                    id: memoId,
                    title: DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short),
                    text: transcription,
                    filePath: nil
                )
                AppLogger.persistence.info("Saved voice memo with real-time transcription")
            }
        } catch {
            AppLogger.fileOperation.error("Failed to save recording: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sub Views

@available(iOS 26.0, *)
struct RealtimeTranscriptionResultView: View {
    @ObservedObject var recorder: RealtimeTranscriptionRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("リアルタイム文字起こし")
                    .font(.headline)
                Spacer()
                if recorder.isTranscribing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("認識中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if recorder.transcribedText.isEmpty {
                        if recorder.isRecording {
                            Text("話しかけてください...")
                                .foregroundColor(.blue)
                        } else {
                            Text("録音を開始してください")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(recorder.transcribedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(minHeight: 100, maxHeight: 200)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

@available(iOS 26.0, *)
struct RealtimeRecordingTimeView: View {
    @ObservedObject var recorder: RealtimeTranscriptionRecorder

    var body: some View {
        VStack(spacing: 8) {
            Text("録音時間: \(formatTime(recorder.recordingDuration))")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(recorder.isRecording ? .red : .secondary)

            if recorder.isRecording {
                HStack(spacing: 8) {
                    Text("録音中...")
                        .font(.caption)
                        .foregroundColor(.red)
                        .opacity(0.8)

                    // Audio level indicator
                    AudioLevelView(audioLevel: recorder.audioLevel)
                        .frame(width: 60, height: 8)
                }
            }
        }
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

@available(iOS 26.0, *)
struct RealtimeRecordingButtonView: View {
    @ObservedObject var recorder: RealtimeTranscriptionRecorder
    let onRecordingComplete: (UUID, URL, String) async -> Void
    let onDismiss: () -> Void
    @Binding var currentMemoId: UUID?

    var body: some View {
        Button(action: {
            Task {
                if recorder.isRecording {
                    // Stop recording
                    guard let audioFileURL = recorder.audioFileURL,
                          let memoId = currentMemoId else {
                        AppLogger.ui.error("No audio file URL or memo ID available")
                        return
                    }

                    let transcription = recorder.transcribedText
                    await recorder.stopRecording()

                    await onRecordingComplete(memoId, audioFileURL, transcription)
                    onDismiss()
                } else {
                    // Start recording
                    recorder.resetTranscription()
                    currentMemoId = UUID()

                    do {
                        try await recorder.startRecording()
                    } catch {
                        AppLogger.ui.error("Failed to start recording: \(error.localizedDescription)")
                    }
                }
            }
        }) {
            HStack {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle.fill")
                    .font(.title)
                Text(recorder.isRecording ? "録音停止" : "録音開始")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(buttonColor)
            .foregroundColor(.white)
            .cornerRadius(12)
            .scaleEffect(recorder.isRecording ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: recorder.isRecording)
        }
    }

    private var buttonColor: Color {
        recorder.isRecording ? .red : .green
    }
}

struct AudioLevelView: View {
    var audioLevel: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .foregroundColor(.gray)
                    .opacity(0.3)
                Rectangle()
                    .foregroundColor(colorForLevel(audioLevel))
                    .frame(width: normalizedWidth(for: audioLevel, in: geometry.size.width))
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }
            .cornerRadius(10)
        }
    }

    private func normalizedWidth(for audioLevel: Float, in totalWidth: CGFloat) -> CGFloat {
        let normalizedLevel = max(0, min(1, audioLevel))
        return CGFloat(normalizedLevel) * totalWidth
    }

    private func colorForLevel(_ level: Float) -> Color {
        if level > 0.8 {
            return .red
        } else if level > 0.5 {
            return .orange
        } else if level > 0.2 {
            return .green
        } else {
            return .blue
        }
    }
}

@available(iOS 26.0, *)
struct RealtimeSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("録音設定") {
                    HStack {
                        Image(systemName: "waveform.circle")
                        Text("録音品質")
                        Spacer()
                        Text("高品質")
                            .foregroundColor(.secondary)
                    }
                }

                Section("音声認識設定") {
                    HStack {
                        Image(systemName: "mic.circle")
                        Text("認識言語")
                        Spacer()
                        Text("日本語")
                            .foregroundColor(.secondary)
                    }
                }

                Section("アプリ情報") {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@available(iOS 26.0, *)
#Preview {
    ContentView()
}
