import SwiftUI
import ComposableArchitecture
import AVFoundation
import WhisperKit
import GoogleMobileAds

@Reducer
struct VoiceMemoDetailFeature {
  @ObservableState
    struct State: Equatable {
        static func == (lhs: VoiceMemoDetailFeature.State, rhs: VoiceMemoDetailFeature.State) -> Bool {
            return lhs.memo.id == rhs.memo.id &&
                   lhs.editedTitle == rhs.editedTitle &&
                   lhs.editedText == rhs.editedText &&
                   lhs.transcription == rhs.transcription &&
                   lhs.isTranscribing == rhs.isTranscribing &&
                   lhs.isPlaying == rhs.isPlaying &&
                   lhs.isEditing == rhs.isEditing &&
                   lhs.showingShareSheet == rhs.showingShareSheet &&
                   lhs.showingSaveAlert == rhs.showingSaveAlert &&
                   lhs.showingFillerWordPreview == rhs.showingFillerWordPreview &&
                   lhs.showingSearchReplace == rhs.showingSearchReplace &&
                   lhs.showingMoreMenu == rhs.showingMoreMenu &&
                   lhs.backgroundTranscriptionState == rhs.backgroundTranscriptionState &&
                   lhs.backgroundProgress == rhs.backgroundProgress &&
                   lhs.additionalRecorderState == rhs.additionalRecorderState
        }
        
    var memo: VoiceMemo
    var editedTitle: String
    var editedText: String
    var transcription: String = "AI文字起こしを開始するには、以下のボタンを押してください。"
    var isTranscribing = false
    var isPlaying = false
    var isEditing = false
    var showingShareSheet = false
    var showingSaveAlert = false
    var showingFillerWordPreview = false
    var showingSearchReplace = false
    var showingMoreMenu = false
    var fillerWordResult: FillerWordRemovalResult?
    var backgroundTranscriptionState: BackgroundTranscriptionState = .idle
    var backgroundProgress: TranscriptionProgress = TranscriptionProgress(
      currentSegment: 0,
      totalSegments: 0,
      processedDuration: 0,
      totalDuration: 0,
      transcribedText: ""
    )
    var additionalRecorderState: AdditionalRecorderState = AdditionalRecorderState()
    
    init(memo: VoiceMemo) {
      self.memo = memo
      self.editedTitle = memo.title
      self.editedText = memo.text
    }
  }
  
  struct AdditionalRecorderState: Equatable {
    var isRecording = false
    var recordingDuration: TimeInterval = 0
  }
  
  enum BackgroundTranscriptionState: Equatable {
    case idle
    case processing
    case paused
    case completed
    case failed(String)
    
    static func == (lhs: BackgroundTranscriptionState, rhs: BackgroundTranscriptionState) -> Bool {
      switch (lhs, rhs) {
      case (.idle, .idle), (.processing, .processing), (.paused, .paused), (.completed, .completed):
        return true
      case (.failed(let lhsError), .failed(let rhsError)):
        return lhsError == rhsError
      default:
        return false
      }
    }
  }

  enum Action: ViewAction, BindableAction {
    case binding(BindingAction<State>)
    case transcriptionCompleted(String)
    case transcriptionFailed(String)
    case backgroundTranscriptionStateChanged(BackgroundTranscriptionState)
    case backgroundProgressUpdated(TranscriptionProgress)
    case additionalRecorderStateChanged(AdditionalRecorderState)
    case fillerWordResultReceived(FillerWordRemovalResult?)
    case memoUpdated(VoiceMemo)
    case view(View)

    enum View {
      case onAppear
      case onDisappear
      case togglePlayback
      case startTranscription
      case startBackgroundTranscription
      case pauseBackgroundTranscription
      case resumeBackgroundTranscription
      case toggleAdditionalRecording
      case toggleEditing
      case showMoreMenu
      case shareButtonTapped
      case previewFillerWordRemoval
      case applyFillerWordRemoval
      case showSearchReplace
      case saveChanges
    }
  }

  @Dependency(\.voiceMemoController) var voiceMemoController
  @Dependency(\.backgroundTranscriptionManager) var backgroundTranscriptionManager
  @Dependency(\.audioRecorder) var audioRecorder
  @Dependency(\.audioPlayerClient) var audioPlayerClient
  @Dependency(\.continuousClock) var clock

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case let .view(viewAction):
        switch viewAction {
        case .onAppear:
          return .run { [memoId = state.memo.id, memo = state.memo] send in
            // Load interstitial ad and refresh memo
            await send(.memoUpdated(voiceMemoController.fetchVoiceMemo(id: memoId) ?? memo))
          }
          
        case .onDisappear:
          return .run { _ in
            // Stop playback and recording if needed
            await audioPlayerClient.stopPlayback()
            audioRecorder.stopRecording()
          }
          
        case .togglePlayback:
          state.isPlaying.toggle()
          return .run { [isPlaying = state.isPlaying, memoId = state.memo.id] _ in
            if isPlaying {
              // UUIDから音声ファイルパスを生成
              let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
              let voiceRecordingsPath = documentsDirectory.appendingPathComponent("VoiceRecordings")
              let filename = "recording-\(memoId.uuidString).m4a"
              let filePath = voiceRecordingsPath.appendingPathComponent(filename).path
              await audioPlayerClient.startPlayback(filePath)
            } else {
              await audioPlayerClient.stopPlayback()
            }
          }
          
        case .startTranscription:
          if state.backgroundTranscriptionState == .idle {
            return .send(.view(.startBackgroundTranscription))
          } else {
            state.isTranscribing = true
            return .run { [memo = state.memo] send in
              do {
                let text = try await transcribeAudio(memo: memo)
                await send(.transcriptionCompleted(text))
              } catch {
                await send(.transcriptionFailed(error.localizedDescription))
              }
            }
          }
          
        case .startBackgroundTranscription:
          return .run { [memo = state.memo] send in
            await backgroundTranscriptionManager.startTranscription(
              audioURL: getAudioURL(for: memo),
              memoId: memo.id
            )
          }
          
        case .pauseBackgroundTranscription:
          return .run { _ in
            backgroundTranscriptionManager.pauseTranscription()
          }
          
        case .resumeBackgroundTranscription:
          return .run { _ in
            await backgroundTranscriptionManager.resumeTranscription()
          }
          
        case .toggleAdditionalRecording:
          if state.additionalRecorderState.isRecording {
            state.additionalRecorderState.isRecording = false
            return .run { _ in
              audioRecorder.stopRecording()
            }
          } else {
            state.additionalRecorderState.isRecording = true
            return .run { [memoId = state.memo.id] send in
              audioRecorder.startAdditionalRecording(for: memoId)
              
              // 録音時間の監視を開始
              while audioRecorder.isRecording {
                try await clock.sleep(for: .milliseconds(100))
                await send(.additionalRecorderStateChanged(AdditionalRecorderState(
                  isRecording: audioRecorder.isRecording,
                  recordingDuration: audioRecorder.recordingDuration
                )))
              }
            }
          }
          
        case .toggleEditing:
          if state.isEditing {
            // Save changes
            state.isEditing = false
            return .send(.view(.saveChanges))
          } else {
            state.isEditing = true
            return .none
          }
          
        case .showMoreMenu:
          state.showingMoreMenu = true
          return .none
          
        case .shareButtonTapped:
          state.showingShareSheet = true
          return .none
          
        case .previewFillerWordRemoval:
          return .run { [memoId = state.memo.id] send in
            let result = voiceMemoController.previewFillerWordRemoval(memoId: memoId)
            await send(.fillerWordResultReceived(result))
          }
          
        case .applyFillerWordRemoval:
          return .run { [memoId = state.memo.id, memo = state.memo] send in
            if let result = voiceMemoController.removeFillerWordsFromMemo(memoId: memoId),
               result.hasChanges {
              let updatedMemo = voiceMemoController.fetchVoiceMemo(id: memoId)
              await send(.memoUpdated(updatedMemo ?? memo))
            }
          }
          
        case .showSearchReplace:
          state.showingSearchReplace = true
          return .none
          
        case .saveChanges:
          return .run { [memo = state.memo, title = state.editedTitle, text = state.editedText] send in
            let success = voiceMemoController.updateVoiceMemo(
              id: memo.id,
              title: title.isEmpty ? "無題" : title,
              text: text
            )
            if success {
              let updatedMemo = voiceMemoController.fetchVoiceMemo(id: memo.id)
              await send(.memoUpdated(updatedMemo ?? memo))
            }
          }
        }
        
      case let .transcriptionCompleted(text):
        state.transcription = text
        state.isTranscribing = false
        return .none
        
      case let .transcriptionFailed(error):
        state.transcription = "AI文字起こし中にエラーが発生しました: \(error)"
        state.isTranscribing = false
        return .none
        
      case let .backgroundTranscriptionStateChanged(newState):
        state.backgroundTranscriptionState = newState
        return .none
        
      case let .backgroundProgressUpdated(progress):
        state.backgroundProgress = progress
        return .none
        
      case let .additionalRecorderStateChanged(recorderState):
        state.additionalRecorderState = recorderState
        return .none
        
      case let .fillerWordResultReceived(result):
        state.fillerWordResult = result
        if result != nil {
          state.showingFillerWordPreview = true
        }
        return .none
        
      case let .memoUpdated(memo):
        state.memo = memo
        return .none
      }
    }
  }
}

// MARK: - Helper Functions
private func transcribeAudio(memo: VoiceMemo) async throws -> String {
  let audioURL = getAudioURL(for: memo)
  let whisper = try await WhisperKit()
  let results = try await whisper.transcribe(
    audioPath: audioURL.path,
    decodeOptions: DecodingOptions(language: "ja")
  )
  return results.map { $0.text }.joined(separator: "\n")
}

private func getAudioURL(for memo: VoiceMemo) -> URL {
  guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
    fatalError("Documents directory not found")
  }
  let voiceRecordingsPath = documentsDirectory.appendingPathComponent("VoiceRecordings")
  let filename = "recording-\(memo.id.uuidString).m4a"
  return voiceRecordingsPath.appendingPathComponent(filename)
}

private func getFilePath(for memoId: UUID) -> String {
  guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
    return ""
  }
  let voiceRecordingsPath = documentsDirectory.appendingPathComponent("VoiceRecordings")
  let filename = "recording-\(memoId.uuidString).m4a"
  return voiceRecordingsPath.appendingPathComponent(filename).path
}

// MARK: - Dependencies
private enum VoiceMemoControllerKey: DependencyKey {
  static let liveValue = VoiceMemoController.shared
}

private enum BackgroundTranscriptionManagerKey: DependencyKey {
  static let liveValue = BackgroundTranscriptionManager.shared
}

private enum AudioRecorderKey: DependencyKey {
  static let liveValue = AudioRecorder()
}

extension DependencyValues {
  var voiceMemoController: VoiceMemoController {
    get { self[VoiceMemoControllerKey.self] }
    set { self[VoiceMemoControllerKey.self] = newValue }
  }
  
  var backgroundTranscriptionManager: BackgroundTranscriptionManager {
    get { self[BackgroundTranscriptionManagerKey.self] }
    set { self[BackgroundTranscriptionManagerKey.self] = newValue }
  }
  
  var audioRecorder: AudioRecorder {
    get { self[AudioRecorderKey.self] }
    set { self[AudioRecorderKey.self] = newValue }
  }
}

// MARK: - View
@ViewAction(for: VoiceMemoDetailFeature.self)
struct VoiceMemoDetailView: View {
  @Bindable var store: StoreOf<VoiceMemoDetailFeature>
  private let admobKey: String
  private let onMemoUpdated: (() -> Void)?
  
  init(store: StoreOf<VoiceMemoDetailFeature>, admobKey: String, onMemoUpdated: (() -> Void)? = nil) {
    self.store = store
    self.admobKey = admobKey
    self.onMemoUpdated = onMemoUpdated
  }
  
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // ファイル情報セクション
        fileInfoSection()
        
        // タイトル編集セクション
        titleEditingSection()
        
        // テキスト編集セクション
        textEditingSection()
        
        // 追加録音セグメント表示
        if !store.memo.segments.isEmpty {
          segmentsSection()
        }
        
        // AI文字起こしセクション
        transcriptionSection()
        
        // メインアクションボタン
        actionButtonsSection()
      }
      .padding()
    }
    .navigationTitle(store.editedTitle)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      send(.onAppear)
    }
    .onDisappear {
      send(.onDisappear)
    }
    .sheet(isPresented: $store.showingShareSheet) {
      ShareSheet(items: createShareItems())
    }
    .alert("保存完了", isPresented: $store.showingSaveAlert) {
      Button("OK") { }
    } message: {
      Text("文字起こし結果が更新されました。")
    }
    .sheet(isPresented: $store.showingFillerWordPreview) {
      FillerWordPreviewView(
        result: store.fillerWordResult,
        onApply: { send(.applyFillerWordRemoval) },
        onCancel: { store.showingFillerWordPreview = false }
      )
    }
    .sheet(isPresented: $store.showingSearchReplace) {
      TextSearchReplaceView(
        text: $store.editedText,
        onDismiss: { store.showingSearchReplace = false },
        onTextChanged: { newText in
          store.editedText = newText
        }
      )
    }
    .actionSheet(isPresented: $store.showingMoreMenu) {
      ActionSheet(
        title: Text("その他の操作"),
        buttons: createMoreMenuButtons()
      )
    }
  }
  
  // MARK: - View Components
  
  private func fileInfoSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("ファイル情報")
        .font(.headline)
      
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("作成日時:")
            .foregroundColor(.secondary)
          Spacer()
          Text(formatDate(store.memo.date))
        }
        
        let filePath = getFilePath(for: store.memo.id)
        if let duration = getAudioDuration(filePath: filePath) {
          HStack {
            Text("録音時間:")
              .foregroundColor(.secondary)
            Spacer()
            Text(formatDuration(duration + store.memo.totalDuration))
          }
        }
        
        if let fileSize = getFileSize(filePath: filePath) {
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
  }
  
  private func titleEditingSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("タイトル")
        .font(.headline)
      
      if store.isEditing {
        TextField("タイトルを入力", text: $store.editedTitle)
          .textFieldStyle(RoundedBorderTextFieldStyle())
      } else {
        Text(store.editedTitle)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.systemGray6))
          .cornerRadius(8)
      }
    }
  }
  
  private func textEditingSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("文字起こし結果")
          .font(.headline)
        
        Spacer()
        
        // 編集モード時のツールバー
        if store.isEditing {
          HStack(spacing: 8) {
            Button(action: { send(.showSearchReplace) }) {
              Image(systemName: "magnifyingglass")
            }
          }
          .font(.title2)
        }
      }
      
      if store.isEditing {
        TextEditor(text: $store.editedText)
          .frame(minHeight: 100)
          .padding(8)
          .background(Color(.systemGray6))
          .cornerRadius(8)
      } else {
        Text(store.editedText.isEmpty ? "文字起こし結果なし" : store.editedText)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.systemGray6))
          .cornerRadius(8)
          .foregroundColor(store.editedText.isEmpty ? .secondary : .primary)
      }
    }
  }
  
  private func segmentsSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("追加録音セグメント")
        .font(.headline)
      
      ForEach(store.memo.segments.indices, id: \.self) { index in
        let segment = store.memo.segments[index]
        HStack {
          Text("セグメント \(index + 1)")
          Spacer()
          Text(formatDuration(segment.duration))
            .foregroundColor(.secondary)
          
          Button("削除") {
            // Handle segment removal through store action
          }
          .font(.caption)
          .foregroundColor(.red)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
      }
      
      Text("合計時間: \(formatDuration(store.memo.totalDuration))")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
  
  private func transcriptionSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("AI文字起こし")
          .font(.headline)
        
        Spacer()
        
        // バックグラウンド処理状態表示
        switch store.backgroundTranscriptionState {
        case .processing:
          Button("一時停止") {
            send(.pauseBackgroundTranscription)
          }
          .font(.caption)
          .foregroundColor(.orange)
        case .paused:
          Button("再開") {
            send(.resumeBackgroundTranscription)
          }
          .font(.caption)
          .foregroundColor(.blue)
        case .completed:
          Text("完了")
            .font(.caption)
            .foregroundColor(.green)
        case .failed(let error):
          Text("エラー")
            .font(.caption)
            .foregroundColor(.red)
        default:
          EmptyView()
        }
      }
      
      // バックグラウンド処理の進捗表示
      if case .processing = store.backgroundTranscriptionState {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("進捗: \(store.backgroundProgress.currentSegment)/\(store.backgroundProgress.totalSegments) セグメント")
            Spacer()
            Text("\(Int(store.backgroundProgress.percentage * 100))%")
          }
          .font(.caption)
          .foregroundColor(.secondary)
          
          ProgressView(value: store.backgroundProgress.percentage)
            .progressViewStyle(LinearProgressViewStyle())
          
          Text("処理時間: \(formatDuration(store.backgroundProgress.processedDuration)) / \(formatDuration(store.backgroundProgress.totalDuration))")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(8)
      }
      
      // 文字起こし結果表示
      let displayText = store.backgroundProgress.transcribedText.isEmpty ? store.transcription : store.backgroundProgress.transcribedText
      
      Text(displayText)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body)
    }
  }
  
  private func actionButtonsSection() -> some View {
    VStack(spacing: 12) {
      // 再生・文字起こしボタン
      HStack(spacing: 12) {
        Button(action: { send(.togglePlayback) }) {
          HStack {
            Image(systemName: store.isPlaying ? "stop.fill" : "play.fill")
            Text(store.isPlaying ? "停止" : "再生")
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(store.isPlaying ? Color.red : Color.green)
          .foregroundColor(.white)
          .cornerRadius(12)
        }
        
        Button(action: { send(.startTranscription) }) {
          HStack {
            Image(systemName: "text.bubble")
            Text(getTranscriptionButtonText())
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(getTranscriptionButtonColor())
          .foregroundColor(.white)
          .cornerRadius(12)
        }
        .disabled(store.isTranscribing || store.backgroundTranscriptionState == .processing)
      }
      
      // その他メニューボタン
      Button(action: { send(.showMoreMenu) }) {
        HStack {
          Image(systemName: "ellipsis.circle")
          Text("その他の操作")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray)
        .foregroundColor(.white)
        .cornerRadius(12)
      }
      .disabled(store.additionalRecorderState.isRecording)
      
      // 追加録音中のUI
      if store.additionalRecorderState.isRecording {
        VStack(spacing: 8) {
          Text("追加録音中...")
            .font(.headline)
            .foregroundColor(.red)
          
          Text("録音時間: \(formatTime(store.additionalRecorderState.recordingDuration))")
            .font(.subheadline)
            .foregroundColor(.secondary)
          
          // 追加録音停止ボタン
          Button(action: { send(.toggleAdditionalRecording) }) {
            HStack {
              Image(systemName: "stop.circle.fill")
              Text("追加録音停止")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(12)
          }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
      }
    }
  }
  
  // MARK: - Helper Functions
  
  private func createShareItems() -> [Any] {
    var items: [Any] = []
    
    let textContent = """
    タイトル: \(store.editedTitle)
    作成日時: \(formatDate(store.memo.date))
    
    文字起こし結果:
    \(store.editedText)
    
    文字起こし結果:
    \(store.transcription)
    """
    items.append(textContent)
    
    let filePath = getFilePath(for: store.memo.id)
    if !filePath.isEmpty {
      let fileURL = URL(fileURLWithPath: filePath)
      if FileManager.default.fileExists(atPath: filePath) {
        items.append(fileURL)
      }
    }
    
    return items
  }
  
  private func createMoreMenuButtons() -> [ActionSheet.Button] {
    var buttons: [ActionSheet.Button] = []
    
    // 編集ボタン
    buttons.append(.default(Text(store.isEditing ? "💾 保存" : "📝 編集")) {
      send(.toggleEditing)
    })
    
    // 録音追加ボタン
    if !store.isEditing {
      buttons.append(.default(Text("🎤 録音を追加")) {
        send(.toggleAdditionalRecording)
      })
    }
    
    // フィラーワード除去ボタン（テキストがある場合のみ）
    if !store.editedText.isEmpty && !store.isEditing {
      buttons.append(.default(Text("✨ フィラーワード除去")) {
        send(.previewFillerWordRemoval)
      })
    }
    
    // 共有ボタン
    buttons.append(.default(Text("📤 共有")) {
      send(.shareButtonTapped)
    })
    
    // キャンセルボタン
    buttons.append(.cancel(Text("キャンセル")))
    
    return buttons
  }
  
  private func getTranscriptionButtonText() -> String {
    switch store.backgroundTranscriptionState {
    case .processing:
      return "処理中..."
    case .paused:
      return "一時停止中"
    case .completed:
      return "完了"
    case .failed(_):
      return "再試行"
    default:
      if store.isTranscribing {
        return "変換中..."
      } else {
        return "文字起こし"
      }
    }
  }
  
  private func getTranscriptionButtonColor() -> Color {
    switch store.backgroundTranscriptionState {
    case .processing:
      return Color.orange
    case .paused:
      return Color.blue
    case .completed:
      return Color.green
    case .failed(_):
      return Color.red
    default:
      return store.isTranscribing ? Color.gray : Color.blue
    }
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
  
  private func getFileSize(filePath: String) -> Int64? {
    guard !filePath.isEmpty else { return nil }
    
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
      return attributes[.size] as? Int64
    } catch {
      return nil
    }
  }
  
  private func getAudioDuration(filePath: String) -> TimeInterval? {
    guard !filePath.isEmpty else { return nil }
    
    let fileURL = URL(fileURLWithPath: filePath)
    
    do {
      let audioFile = try AVAudioFile(forReading: fileURL)
      let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
      return duration
    } catch {
      return nil
    }
  }
}
