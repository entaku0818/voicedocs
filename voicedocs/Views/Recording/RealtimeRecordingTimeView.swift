import SwiftUI

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
