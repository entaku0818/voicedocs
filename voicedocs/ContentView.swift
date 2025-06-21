import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()
    @State private var showingQualitySettings = false
    @State private var showingLanguageSettings = false
    @State private var showingError = false
    @State private var showingVoiceMemoList = false
    @State private var showingSettings = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {

        VStack(spacing: 20) {
            // 設定エリア
            VStack(spacing: 8) {

                if !speechRecognitionManager.isAvailable {
                    Text("音声認識が利用できません")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)

            // 音声認識結果表示
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("音声認識結果")
                        .font(.headline)
                    Spacer()
                    if speechRecognitionManager.isRecognizing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("認識中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if speechRecognitionManager.recognitionQuality > 0 {
                        Text("精度: \(Int(speechRecognitionManager.recognitionQuality * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                ScrollView {
                    Text(speechRecognitionManager.transcribedText.isEmpty ? "録音を開始してください" : speechRecognitionManager.transcribedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 100, maxHeight: 200)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }

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



            // 録音ボタン
            Button(action: {
                Task {
                    if audioRecorder.isRecording {
                        // 録音停止
                        audioRecorder.stopRecording()
                        await speechRecognitionManager.stopSpeechRecognition()
                        // 前のページに戻る
                        dismiss()
                    } else {
                        // 録音開始
                        do {
                            audioRecorder.startRecording()
                            try await speechRecognitionManager.startSpeechRecognition()
                        } catch {
                            print("Failed to start recording: \(error)")
                            speechRecognitionManager.lastError = .configurationFailed
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
            }
        }

        .sheet(isPresented: $showingQualitySettings) {
            QualitySettingsView(audioRecorder: audioRecorder)
        }
        .sheet(isPresented: $showingLanguageSettings) {
            LanguageSettingsView(speechRecognitionManager: speechRecognitionManager)
        }
        .sheet(isPresented: $showingVoiceMemoList) {
            VoiceMemoListView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(audioRecorder: audioRecorder, speechRecognitionManager: speechRecognitionManager)
        }
        .onChange(of: speechRecognitionManager.lastError) { error in
            showingError = error != nil
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

struct LanguageSettingsView: View {
    @ObservedObject var speechRecognitionManager: SpeechRecognitionManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("音声認識言語") {
                    ForEach(speechRecognitionManager.getSupportedLanguages(), id: \.self) { language in
                        HStack {
                            Text(language.displayName)
                            Spacer()
                            if speechRecognitionManager.currentLanguage == language {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            speechRecognitionManager.changeLanguage(to: language)
                        }
                    }
                }
                
                Section("設定について") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("日本語: 日本語の音声認識に最適化")
                            .font(.caption)
                        Text("English: 英語の音声認識に最適化")
                            .font(.caption)
                        Text("録音中は言語を変更できません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("音声認識設定")
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

struct SettingsView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var speechRecognitionManager: SpeechRecognitionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingQualitySettings = false
    @State private var showingLanguageSettings = false
    
    var body: some View {
        NavigationView {
            List {
                Section("録音設定") {
                    HStack {
                        Image(systemName: "waveform.circle")
                        Text("録音品質")
                        Spacer()
                        Text(audioRecorder.recordingQuality.displayName)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        showingQualitySettings = true
                    }
                }
                
                Section("音声認識設定") {
                    HStack {
                        Image(systemName: "mic.circle")
                        Text("認識言語")
                        Spacer()
                        Text(speechRecognitionManager.currentLanguage.displayName)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        showingLanguageSettings = true
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("認識状態")
                        Spacer()
                        Text(speechRecognitionManager.isAvailable ? "利用可能" : "利用不可")
                            .foregroundColor(speechRecognitionManager.isAvailable ? .green : .red)
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
                    
                    HStack {
                        Image(systemName: "doc.text")
                        Text("ライセンス")
                        Spacer()
                        Image(systemName: "chevron.right")
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
        .sheet(isPresented: $showingQualitySettings) {
            QualitySettingsView(audioRecorder: audioRecorder)
        }
        .sheet(isPresented: $showingLanguageSettings) {
            LanguageSettingsView(speechRecognitionManager: speechRecognitionManager)
        }
    }
}

#Preview {
    ContentView()
}
