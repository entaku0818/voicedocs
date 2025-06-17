import Foundation
import SwiftUI
import WhisperKit
import AVFoundation
import GoogleMobileAds

struct VoiceMemoDetailView: View {
    private let memo: VoiceMemo
    private let admobKey: String
    private let onMemoUpdated: (() -> Void)?

    @State private var editedTitle: String
    @State private var editedText: String
    @State private var transcription: String = "AI文字起こしを開始するには、以下のボタンを押してください。"
    @State private var isTranscribing = false
    @State private var isPlaying = false
    @State private var isEditing = false
    @State private var showingShareSheet = false
    @State private var showingSaveAlert = false
    @State private var currentMemo: VoiceMemo
    @State private var player: AVPlayer?
    @State private var interstitial: GADInterstitialAd?
    @StateObject private var additionalRecorder = AudioRecorder()
    @State private var showingFillerWordPreview = false
    @State private var fillerWordResult: FillerWordRemovalResult?
    
    private let voiceMemoController = VoiceMemoController.shared

    init(memo: VoiceMemo, admobKey: String, onMemoUpdated: (() -> Void)? = nil) {
        self.memo = memo
        self.admobKey = admobKey
        self.onMemoUpdated = onMemoUpdated
        self._editedTitle = State(initialValue: memo.title)
        self._editedText = State(initialValue: memo.text)
        self._currentMemo = State(initialValue: memo)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ファイル情報セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("ファイル情報")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("作成日時:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatDate(memo.date))
                        }
                        
                        if let duration = voiceMemoController.getAudioDuration(filePath: memo.filePath) {
                            HStack {
                                Text("録音時間:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatDuration(duration + currentMemo.totalDuration))
                            }
                        }
                        
                        if let fileSize = voiceMemoController.getFileSize(filePath: memo.filePath) {
                            HStack {
                                Text("ファイルサイズ:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatFileSize(fileSize))
                            }
                        }
                    }
                    .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // タイトル編集セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("タイトル")
                        .font(.headline)
                    
                    if isEditing {
                        TextField("タイトルを入力", text: $editedTitle)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    } else {
                        Text(editedTitle)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
                
                // テキスト編集セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("メモ")
                        .font(.headline)
                    
                    if isEditing {
                        TextEditor(text: $editedText)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    } else {
                        Text(editedText.isEmpty ? "メモなし" : editedText)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .foregroundColor(editedText.isEmpty ? .secondary : .primary)
                    }
                }
                
                // 追加録音セグメント表示
                if !currentMemo.segments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("追加録音セグメント")
                            .font(.headline)
                        
                        ForEach(currentMemo.segments.indices, id: \.self) { index in
                            let segment = currentMemo.segments[index]
                            HStack {
                                Text("セグメント \(index + 1)")
                                Spacer()
                                Text(formatDuration(segment.duration))
                                    .foregroundColor(.secondary)
                                
                                Button("削除") {
                                    removeSegment(segment)
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        
                        Text("合計時間: \(formatDuration(currentMemo.totalDuration))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // AI文字起こしセクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI文字起こし")
                        .font(.headline)
                    
                    Text(transcription)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.body)
                }
                
                // 操作ボタン
                VStack(spacing: 12) {
                    // 再生・文字起こしボタン
                    HStack(spacing: 12) {
                        Button(action: togglePlayback) {
                            HStack {
                                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                Text(isPlaying ? "停止" : "再生")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isPlaying ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button(action: showInterstitialAd) {
                            HStack {
                                Image(systemName: "text.bubble")
                                Text(isTranscribing ? "変換中..." : "文字起こし")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isTranscribing ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isTranscribing)
                    }
                    
                    // 追加録音ボタン
                    Button(action: toggleAdditionalRecording) {
                        HStack {
                            Image(systemName: additionalRecorder.isRecording ? "stop.circle.fill" : "mic.badge.plus")
                            Text(additionalRecorder.isRecording ? "追加録音停止" : "録音を追加")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(additionalRecorder.isRecording ? Color.red : Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .scaleEffect(additionalRecorder.isRecording ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: additionalRecorder.isRecording)
                    }
                    
                    // 追加録音中のUI
                    if additionalRecorder.isRecording {
                        VStack(spacing: 8) {
                            Text("追加録音中...")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Text("録音時間: \(formatTime(additionalRecorder.recordingDuration))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // 音声レベル表示
                            VStack(alignment: .leading, spacing: 4) {
                                Text("音声レベル")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .foregroundColor(.gray)
                                            .opacity(0.3)
                                        Rectangle()
                                            .foregroundColor(additionalRecorder.audioLevel > 0.8 ? .red : additionalRecorder.audioLevel > 0.5 ? .orange : .green)
                                            .frame(width: CGFloat(additionalRecorder.audioLevel) * geometry.size.width)
                                            .animation(.easeInOut(duration: 0.1), value: additionalRecorder.audioLevel)
                                    }
                                    .cornerRadius(10)
                                }
                                .frame(height: 20)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // フィラーワード除去ボタン（テキストがある場合のみ表示）
                    if !editedText.isEmpty && !isEditing {
                        Button(action: previewFillerWordRemoval) {
                            HStack {
                                Image(systemName: "text.redaction")
                                Text("フィラーワード除去")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(additionalRecorder.isRecording)
                    }
                    
                    // 編集・共有ボタン
                    HStack(spacing: 12) {
                        Button(action: toggleEditing) {
                            HStack {
                                Image(systemName: isEditing ? "checkmark" : "pencil")
                                Text(isEditing ? "保存" : "編集")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isEditing ? Color.orange : Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(additionalRecorder.isRecording)
                        
                        Button(action: { showingShareSheet = true }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("共有")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(additionalRecorder.isRecording)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(editedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadInterstitialAd()
            refreshMemo()
        }
        .onDisappear {
            stopPlayback()
            if additionalRecorder.isRecording {
                additionalRecorder.stopRecording()
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: createShareItems())
        }
        .alert("保存完了", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text("メモが更新されました。")
        }
        .sheet(isPresented: $showingFillerWordPreview) {
            FillerWordPreviewView(
                result: fillerWordResult,
                onApply: applyFillerWordRemoval,
                onCancel: { showingFillerWordPreview = false }
            )
        }
    }

    private func loadInterstitialAd() {
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: admobKey, request: request) { ad, error in
            if let error = error {
                print("Failed to load interstitial ad: \(error.localizedDescription)")
                return
            }
            interstitial = ad
        }
    }

    private func showInterstitialAd() {
        if let ad = interstitial {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                print("No root view controller found")

                return
            }
            Task {
                await transcribeAudio()
            }
            ad.present(fromRootViewController: rootViewController)
        } else {
            print("Ad wasn't ready")
            Task {
                await transcribeAudio()
            }
        }
    }


    private func transcribeAudio() async {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            DispatchQueue.main.async {
                transcription = "ドキュメントディレクトリのパスを取得できませんでした。"
            }
            return
        }

        let filePathComponent = (memo.filePath as NSString).lastPathComponent
        let audioURL = documentsDirectory.appendingPathComponent(filePathComponent)

        DispatchQueue.main.async {
            isTranscribing = true
            transcription = "AI文字起こしを取得中..."
        }

        do {
            let whisper = try await WhisperKit()
            let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: DecodingOptions(language: "ja"))

            DispatchQueue.main.async {
                transcription = results.map { $0.text }.joined(separator: "\n")

                isTranscribing = false
            }
        } catch {
            DispatchQueue.main.async {
                transcription = "AI文字起こし中にエラーが発生しました: \(error.localizedDescription)"
                isTranscribing = false
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let filePathComponent = (memo.filePath as NSString).lastPathComponent
            let audioURL = documentsDirectory.appendingPathComponent(filePathComponent)

            do {
                player = AVPlayer(url: audioURL)
                player?.play()
            } catch {
                print("Failed to load audio file: \(error.localizedDescription)")
            }
        }
        isPlaying.toggle()
    }

    private func stopPlayback() {
        player?.pause()
        isPlaying = false
    }
    
    private func toggleEditing() {
        if isEditing {
            // 保存処理
            let success = voiceMemoController.updateVoiceMemo(
                id: memo.id,
                title: editedTitle.isEmpty ? "無題" : editedTitle,
                text: editedText
            )
            
            if success {
                showingSaveAlert = true
                onMemoUpdated?()
            }
        }
        isEditing.toggle()
    }
    
    private func createShareItems() -> [Any] {
        var items: [Any] = []
        
        // テキスト内容
        let textContent = """
        タイトル: \(editedTitle)
        作成日時: \(formatDate(memo.date))
        
        メモ:
        \(editedText)
        
        文字起こし結果:
        \(transcription)
        """
        items.append(textContent)
        
        // 音声ファイル
        if !memo.filePath.isEmpty {
            let fileURL = URL(fileURLWithPath: memo.filePath)
            if FileManager.default.fileExists(atPath: memo.filePath) {
                items.append(fileURL)
            }
        }
        
        return items
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func toggleAdditionalRecording() {
        if additionalRecorder.isRecording {
            additionalRecorder.stopRecording()
            // 録音完了後にメモ情報を更新
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                refreshMemo()
                onMemoUpdated?()
            }
        } else {
            additionalRecorder.startAdditionalRecording(for: memo.id)
        }
    }
    
    private func refreshMemo() {
        let memos = voiceMemoController.fetchVoiceMemos()
        if let updatedMemo = memos.first(where: { $0.id == memo.id }) {
            currentMemo = updatedMemo
        }
    }
    
    private func removeSegment(_ segment: AudioSegment) {
        let success = voiceMemoController.removeSegmentFromMemo(
            memoId: memo.id,
            segmentId: segment.id
        )
        
        if success {
            // セグメントファイルを削除
            _ = voiceMemoController.deleteAudioFile(filePath: segment.filePath)
            refreshMemo()
            onMemoUpdated?()
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
    
    // MARK: - フィラーワード除去機能
    
    private func previewFillerWordRemoval() {
        fillerWordResult = voiceMemoController.previewFillerWordRemoval(memoId: memo.id)
        if fillerWordResult != nil {
            showingFillerWordPreview = true
        }
    }
    
    private func applyFillerWordRemoval() {
        guard let result = voiceMemoController.removeFillerWordsFromMemo(memoId: memo.id) else {
            return
        }
        
        if result.hasChanges {
            editedText = result.cleanedText
            refreshMemo()
            onMemoUpdated?()
            showingSaveAlert = true
        }
        
        showingFillerWordPreview = false
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 更新処理は不要
    }
}

#Preview {
    VoiceMemoDetailView(memo: VoiceMemo(id: UUID(), title: "Sample Memo", text: "This is a sample memo.", date: Date(), filePath: "/path/to/file"), admobKey: "")
}
