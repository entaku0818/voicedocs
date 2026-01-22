import SwiftUI
import os.log

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
