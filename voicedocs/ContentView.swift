import SwiftUI
import os.log

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

#Preview {
    ContentView()
}
