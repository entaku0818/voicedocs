import SwiftUI
import ComposableArchitecture
import AVFoundation
import WhisperKit
import GoogleMobileAds

struct VoiceMemoDetailFeature: Reducer {
  struct State: Equatable {
    static func == (lhs: State, rhs: State) -> Bool {
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
    var audioLevel: Float = 0
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

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case view(ViewAction)
    
    static func == (lhs: Action, rhs: Action) -> Bool {
      switch (lhs, rhs) {
      case (.binding(let lhsAction), .binding(let rhsAction)):
        return lhsAction.keyPath == rhsAction.keyPath
      case (.view(let lhsAction), .view(let rhsAction)):
        return lhsAction == rhsAction
      case (.transcriptionCompleted(let lhsText), .transcriptionCompleted(let rhsText)):
        return lhsText == rhsText
      case (.transcriptionFailed(let lhsError), .transcriptionFailed(let rhsError)):
        return lhsError == rhsError
      case (.backgroundTranscriptionStateChanged(let lhsState), .backgroundTranscriptionStateChanged(let rhsState)):
        return lhsState == rhsState
      case (.backgroundProgressUpdated(let lhsProgress), .backgroundProgressUpdated(let rhsProgress)):
        return lhsProgress == rhsProgress
      case (.additionalRecorderStateChanged(let lhsState), .additionalRecorderStateChanged(let rhsState)):
        return lhsState == rhsState
      case (.fillerWordResultReceived(let lhsResult), .fillerWordResultReceived(let rhsResult)):
        return lhsResult == rhsResult
      case (.memoUpdated(let lhsMemo), .memoUpdated(let rhsMemo)):
        return lhsMemo.id == rhsMemo.id
      default:
        return false
      }
    }
    
    // Internal actions
    case transcriptionCompleted(String)
    case transcriptionFailed(String)
    case backgroundTranscriptionStateChanged(BackgroundTranscriptionState)
    case backgroundProgressUpdated(TranscriptionProgress)
    case additionalRecorderStateChanged(AdditionalRecorderState)
    case fillerWordResultReceived(FillerWordRemovalResult?)
    case memoUpdated(VoiceMemo)

    enum ViewAction: Equatable {
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
  @Dependency(\.continuousClock) var clock

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case let .view(viewAction):
        return handleViewAction(state: &state, action: viewAction)
        
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
  
  private func handleViewAction(state: inout State, action: Action.ViewAction) -> Effect<Action> {
    switch action {
    case .onAppear:
      return .run { send in
        // Load interstitial ad and refresh memo
        await send(.memoUpdated(voiceMemoController.fetchVoiceMemo(id: state.memo.id) ?? state.memo))
      }
      
    case .onDisappear:
      return .run { _ in
        // Stop playback and recording if needed
        audioRecorder.stopRecording()
      }
      
    case .togglePlayback:
      state.isPlaying.toggle()
      return .run { [isPlaying = state.isPlaying, memo = state.memo] _ in
        if isPlaying {
          await audioRecorder.startPlayback(filePath: memo.filePath)
        } else {
          await audioRecorder.stopPlayback()
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
        return .run { _ in
          audioRecorder.stopRecording()
        }
      } else {
        return .run { [memoId = state.memo.id] _ in
          audioRecorder.startAdditionalRecording(for: memoId)
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
      return .run { [memoId = state.memo.id] send in
        if let result = voiceMemoController.removeFillerWordsFromMemo(memoId: memoId),
           result.hasChanges {
          let updatedMemo = voiceMemoController.fetchVoiceMemo(id: memoId)
          await send(.memoUpdated(updatedMemo ?? state.memo))
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
  let filePathComponent = (memo.filePath as NSString).lastPathComponent
  return voiceRecordingsPath.appendingPathComponent(filePathComponent)
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
struct VoiceMemoDetailView: View {
  let store: StoreOf<VoiceMemoDetailFeature>
  private let admobKey: String
  private let onMemoUpdated: (() -> Void)?
  
  init(store: StoreOf<VoiceMemoDetailFeature>, admobKey: String, onMemoUpdated: (() -> Void)? = nil) {
    self.store = store
    self.admobKey = admobKey
    self.onMemoUpdated = onMemoUpdated
  }
  
  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // ファイル情報セクション
          fileInfoSection(viewStore: viewStore)
          
          // タイトル編集セクション
          titleEditingSection(viewStore: viewStore)
          
          // テキスト編集セクション
          textEditingSection(viewStore: viewStore)
          
          // 追加録音セグメント表示
          if !viewStore.memo.segments.isEmpty {
            segmentsSection(viewStore: viewStore)
          }
          
          // AI文字起こしセクション
          transcriptionSection(viewStore: viewStore)
          
          // メインアクションボタン
          actionButtonsSection(viewStore: viewStore)
        }
        .padding()
      }
      .navigationTitle(viewStore.editedTitle)
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        viewStore.send(.view(.onAppear))
      }
      .onDisappear {
        viewStore.send(.view(.onDisappear))
      }
      .sheet(isPresented: viewStore.binding(\.$showingShareSheet)) {
        ShareSheet(items: createShareItems(viewStore: viewStore))
      }
      .alert("保存完了", isPresented: viewStore.binding(\.$showingSaveAlert)) {
        Button("OK") { }
      } message: {
        Text("メモが更新されました。")
      }
      .sheet(isPresented: viewStore.binding(\.$showingFillerWordPreview)) {
        FillerWordPreviewView(
          result: viewStore.fillerWordResult,
          onApply: { viewStore.send(.view(.applyFillerWordRemoval)) },
          onCancel: { viewStore.send(.binding(.set(\.$showingFillerWordPreview, false))) }
        )
      }
      .sheet(isPresented: viewStore.binding(\.$showingSearchReplace)) {
        TextSearchReplaceView(
          text: viewStore.binding(\.$editedText),
          onDismiss: { viewStore.send(.binding(.set(\.$showingSearchReplace, false))) },
          onTextChanged: { newText in
            viewStore.send(.binding(.set(\.$editedText, newText)))
          }
        )
      }
      .actionSheet(isPresented: viewStore.binding(\.$showingMoreMenu)) {
        ActionSheet(
          title: Text("その他の操作"),
          buttons: createMoreMenuButtons(viewStore: viewStore)
        )
      }
    }
  }
  
  // MARK: - View Components
  
  private func fileInfoSection(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("ファイル情報")
        .font(.headline)
      
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("作成日時:")
            .foregroundColor(.secondary)
          Spacer()
          Text(formatDate(viewStore.memo.date))
        }
        
        if let duration = getAudioDuration(filePath: viewStore.memo.filePath) {
          HStack {
            Text("録音時間:")
              .foregroundColor(.secondary)
            Spacer()
            Text(formatDuration(duration + viewStore.memo.totalDuration))
          }
        }
        
        if let fileSize = getFileSize(filePath: viewStore.memo.filePath) {
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
  
  private func titleEditingSection(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("タイトル")
        .font(.headline)
      
      if viewStore.isEditing {
        TextField("タイトルを入力", text: viewStore.binding(\.$editedTitle))
          .textFieldStyle(RoundedBorderTextFieldStyle())
      } else {
        Text(viewStore.editedTitle)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.systemGray6))
          .cornerRadius(8)
      }
    }
  }
  
  private func textEditingSection(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("メモ")
          .font(.headline)
        
        Spacer()
        
        // 編集モード時のツールバー
        if viewStore.isEditing {
          HStack(spacing: 8) {
            Button(action: { viewStore.send(.view(.showSearchReplace)) }) {
              Image(systemName: "magnifyingglass")
            }
          }
          .font(.title2)
        }
      }
      
      if viewStore.isEditing {
        TextEditor(text: viewStore.binding(\.$editedText))
          .frame(minHeight: 100)
          .padding(8)
          .background(Color(.systemGray6))
          .cornerRadius(8)
      } else {
        Text(viewStore.editedText.isEmpty ? "メモなし" : viewStore.editedText)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.systemGray6))
          .cornerRadius(8)
          .foregroundColor(viewStore.editedText.isEmpty ? .secondary : .primary)
      }
    }
  }
  
  private func segmentsSection(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("追加録音セグメント")
        .font(.headline)
      
      ForEach(viewStore.memo.segments.indices, id: \.self) { index in
        let segment = viewStore.memo.segments[index]
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
      
      Text("合計時間: \(formatDuration(viewStore.memo.totalDuration))")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
  
  private func transcriptionSection(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("AI文字起こし")
          .font(.headline)
        
        Spacer()
        
        // バックグラウンド処理状態表示
        switch viewStore.backgroundTranscriptionState {
        case .processing:
          Button("一時停止") {
            viewStore.send(.view(.pauseBackgroundTranscription))
          }
          .font(.caption)
          .foregroundColor(.orange)
        case .paused:
          Button("再開") {
            viewStore.send(.view(.resumeBackgroundTranscription))
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
      if case .processing = viewStore.backgroundTranscriptionState {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("進捗: \(viewStore.backgroundProgress.currentSegment)/\(viewStore.backgroundProgress.totalSegments) セグメント")
            Spacer()
            Text("\(Int(viewStore.backgroundProgress.percentage * 100))%")
          }
          .font(.caption)
          .foregroundColor(.secondary)
          
          ProgressView(value: viewStore.backgroundProgress.percentage)
            .progressViewStyle(LinearProgressViewStyle())
          
          Text("処理時間: \(formatDuration(viewStore.backgroundProgress.processedDuration)) / \(formatDuration(viewStore.backgroundProgress.totalDuration))")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(8)
      }
      
      // 文字起こし結果表示
      let displayText = viewStore.backgroundProgress.transcribedText.isEmpty ? viewStore.transcription : viewStore.backgroundProgress.transcribedText
      
      Text(displayText)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body)
    }
  }
  
  private func actionButtonsSection(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> some View {
    VStack(spacing: 12) {
      // 再生・文字起こしボタン
      HStack(spacing: 12) {
        Button(action: { viewStore.send(.view(.togglePlayback)) }) {
          HStack {
            Image(systemName: viewStore.isPlaying ? "stop.fill" : "play.fill")
            Text(viewStore.isPlaying ? "停止" : "再生")
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(viewStore.isPlaying ? Color.red : Color.green)
          .foregroundColor(.white)
          .cornerRadius(12)
        }
        
        Button(action: { viewStore.send(.view(.startTranscription)) }) {
          HStack {
            Image(systemName: "text.bubble")
            Text(getTranscriptionButtonText(viewStore: viewStore))
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(getTranscriptionButtonColor(viewStore: viewStore))
          .foregroundColor(.white)
          .cornerRadius(12)
        }
        .disabled(viewStore.isTranscribing || viewStore.backgroundTranscriptionState == .processing)
      }
      
      // その他メニューボタン
      Button(action: { viewStore.send(.view(.showMoreMenu)) }) {
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
      .disabled(viewStore.additionalRecorderState.isRecording)
      
      // 追加録音中のUI
      if viewStore.additionalRecorderState.isRecording {
        VStack(spacing: 8) {
          Text("追加録音中...")
            .font(.headline)
            .foregroundColor(.red)
          
          Text("録音時間: \(formatTime(viewStore.additionalRecorderState.recordingDuration))")
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
                  .foregroundColor(viewStore.additionalRecorderState.audioLevel > 0.8 ? .red : viewStore.additionalRecorderState.audioLevel > 0.5 ? .orange : .green)
                  .frame(width: CGFloat(viewStore.additionalRecorderState.audioLevel) * geometry.size.width)
                  .animation(.easeInOut(duration: 0.1), value: viewStore.additionalRecorderState.audioLevel)
              }
              .cornerRadius(10)
            }
            .frame(height: 20)
          }
          
          // 追加録音停止ボタン
          Button(action: { viewStore.send(.view(.toggleAdditionalRecording)) }) {
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
  
  private func createShareItems(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> [Any] {
    var items: [Any] = []
    
    let textContent = """
    タイトル: \(viewStore.editedTitle)
    作成日時: \(formatDate(viewStore.memo.date))
    
    メモ:
    \(viewStore.editedText)
    
    文字起こし結果:
    \(viewStore.transcription)
    """
    items.append(textContent)
    
    if !viewStore.memo.filePath.isEmpty {
      let fileURL = URL(fileURLWithPath: viewStore.memo.filePath)
      if FileManager.default.fileExists(atPath: viewStore.memo.filePath) {
        items.append(fileURL)
      }
    }
    
    return items
  }
  
  private func createMoreMenuButtons(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> [ActionSheet.Button] {
    var buttons: [ActionSheet.Button] = []
    
    // 編集ボタン
    buttons.append(.default(Text(viewStore.isEditing ? "💾 保存" : "📝 編集")) {
      viewStore.send(.view(.toggleEditing))
    })
    
    // 録音追加ボタン
    if !viewStore.isEditing {
      buttons.append(.default(Text("🎤 録音を追加")) {
        viewStore.send(.view(.toggleAdditionalRecording))
      })
    }
    
    // フィラーワード除去ボタン（テキストがある場合のみ）
    if !viewStore.editedText.isEmpty && !viewStore.isEditing {
      buttons.append(.default(Text("✨ フィラーワード除去")) {
        viewStore.send(.view(.previewFillerWordRemoval))
      })
    }
    
    // 共有ボタン
    buttons.append(.default(Text("📤 共有")) {
      viewStore.send(.view(.shareButtonTapped))
    })
    
    // キャンセルボタン
    buttons.append(.cancel(Text("キャンセル")))
    
    return buttons
  }
  
  private func getTranscriptionButtonText(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> String {
    switch viewStore.backgroundTranscriptionState {
    case .processing:
      return "処理中..."
    case .paused:
      return "一時停止中"
    case .completed:
      return "完了"
    case .failed(_):
      return "再試行"
    default:
      if viewStore.isTranscribing {
        return "変換中..."
      } else {
        return "文字起こし"
      }
    }
  }
  
  private func getTranscriptionButtonColor(viewStore: ViewStoreOf<VoiceMemoDetailFeature>) -> Color {
    switch viewStore.backgroundTranscriptionState {
    case .processing:
      return Color.orange
    case .paused:
      return Color.blue
    case .completed:
      return Color.green
    case .failed(_):
      return Color.red
    default:
      return viewStore.isTranscribing ? Color.gray : Color.blue
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