import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()
    @State private var showingQualitySettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 録音品質設定
                HStack {
                    Text("品質: \(audioRecorder.recordingQuality.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("設定") {
                        showingQualitySettings = true
                    }
                    .font(.caption)
                    .disabled(audioRecorder.isRecording)
                }
                .padding(.horizontal)
                
                // 音声認識結果表示
                Text(speechRecognitionManager.transcribedText.isEmpty ? "録音を開始してください" : speechRecognitionManager.transcribedText)
                    .padding()
                    .frame(minHeight: 100)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                // 録音時間表示（常に表示、録音中は更新）
                VStack(spacing: 8) {
                    Text("録音時間: \(formatTime(audioRecorder.recordingDuration))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(audioRecorder.isRecording ? .red : .secondary)
                    
                    if audioRecorder.isRecording {
                        Text("録音中...")
                            .font(.caption)
                            .foregroundColor(.red)
                            .opacity(0.8)
                    }
                }

                // 音声レベル表示
                VStack(alignment: .leading, spacing: 4) {
                    Text("音声レベル")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AudioLevelView(audioLevel: audioRecorder.audioLevel)
                        .frame(height: 20)
                }
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
                    HStack {
                        Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "record.circle.fill")
                            .font(.title)
                        Text(audioRecorder.isRecording ? "録音停止" : "録音開始")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(audioRecorder.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .scaleEffect(audioRecorder.isRecording ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: audioRecorder.isRecording)
                }
                .disabled(speechRecognitionManager.isRecognizing && !audioRecorder.isRecording)
            }
            .padding()
            .navigationTitle("音声録音")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingQualitySettings) {
            QualitySettingsView(audioRecorder: audioRecorder)
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

struct QualitySettingsView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("録音品質") {
                    ForEach(RecordingQuality.allCases, id: \.self) { quality in
                        HStack {
                            Text(quality.displayName)
                            Spacer()
                            if audioRecorder.recordingQuality == quality {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            audioRecorder.setRecordingQuality(quality)
                        }
                    }
                }
                
                Section("品質について") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("標準品質: 22kHz, 中品質")
                            .font(.caption)
                        Text("高品質: 44kHz, 高品質")
                            .font(.caption)
                        Text("高品質を選択するとファイルサイズが大きくなります")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("録音設定")
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

#Preview {
    ContentView()
}
