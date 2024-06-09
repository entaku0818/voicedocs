import SwiftUI

struct ContentView: View {
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()

    var body: some View {
        VStack {
            Text(speechRecognitionManager.transcribedText)
                .padding()

            AudioLevelView(audioLevel: speechRecognitionManager.audioLevel)
                .frame(height: 20)
                .padding()

            HStack {
                Button(action: {
                    Task {
                        do {
                            try await speechRecognitionManager.startRecording()
                        } catch {
                            print("Failed to start recording: \(error)")
                        }
                    }
                }) {
                    Text("Start Recording")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button(action: {
                    speechRecognitionManager.stopRecording()
                }) {
                    Text("Stop Recording")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
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
