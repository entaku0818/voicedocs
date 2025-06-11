import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()

    var body: some View {
        VStack(spacing: 20) {
            // 音声認識結果表示
            Text(speechRecognitionManager.transcribedText.isEmpty ? "録音を開始してください" : speechRecognitionManager.transcribedText)
                .padding()
                .frame(minHeight: 100)
                .background(Color(.systemGray6))
                .cornerRadius(10)

            // 録音時間表示
            if audioRecorder.isRecording {
                Text("録音時間: \(formatTime(audioRecorder.recordingDuration))")
                    .font(.headline)
                    .foregroundColor(.red)
            }

            // 音声レベル表示
            AudioLevelView(audioLevel: audioRecorder.audioLevel)
                .frame(height: 20)
                .padding(.horizontal)

            // 録音ボタン
            Button(action: {
                Task {
                    if audioRecorder.isRecording {
                        // 録音停止
                        audioRecorder.stopRecording()
                        speechRecognitionManager.stopSpeechRecognition()
                    } else {
                        // 録音開始
                        do {
                            audioRecorder.startRecording()
                            try await speechRecognitionManager.startSpeechRecognition()
                        } catch {
                            print("Failed to start recording: \(error)")
                        }
                    }
                }
            }) {
                Text(audioRecorder.isRecording ? "録音停止" : "録音開始")
                    .font(.title2)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(audioRecorder.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(speechRecognitionManager.isRecognizing && !audioRecorder.isRecording)
        }
        .padding()
        .navigationTitle("音声録音")
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
                    .foregroundColor(.blue)
                    .frame(width: normalizedWidth(for: audioLevel, in: geometry.size.width))
                    .animation(.easeInOut(duration: 0.2), value: audioLevel)
            }
            .cornerRadius(10)
        }
    }

    private func normalizedWidth(for audioLevel: Float, in totalWidth: CGFloat) -> CGFloat {
        let minLevel: Float = -60
        let maxLevel: Float = 0
        let clampedLevel = max(min(audioLevel, maxLevel), minLevel)
        return CGFloat((clampedLevel - minLevel) / (maxLevel - minLevel)) * totalWidth
    }
}

#Preview {
    ContentView()
}
