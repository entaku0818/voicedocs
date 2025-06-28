import SwiftUI
import ComposableArchitecture
import AVFoundation
import WhisperKit
import GoogleMobileAds

enum TranscriptionDisplayMode: String, CaseIterable {
  case apple = "文字起こし"
  case ai = "AI文字起こし"
}

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
                   lhs.isAppleTranscribing == rhs.isAppleTranscribing &&
                   lhs.appleTranscription == rhs.appleTranscription &&
                   lhs.currentTranscriptionDisplay == rhs.currentTranscriptionDisplay &&
                   lhs.showingTitleEditModal == rhs.showingTitleEditModal &&
                   lhs.isPlaying == rhs.isPlaying &&
                   lhs.showingShareSheet == rhs.showingShareSheet &&
                   lhs.showingSaveAlert == rhs.showingSaveAlert &&
                   lhs.showingFillerWordPreview == rhs.showingFillerWordPreview &&
                   lhs.showingMoreMenu == rhs.showingMoreMenu &&
                   lhs.backgroundTranscriptionState == rhs.backgroundTranscriptionState &&
                   lhs.backgroundProgress == rhs.backgroundProgress &&
                   lhs.additionalRecorderState == rhs.additionalRecorderState &&
                   lhs.playbackProgress == rhs.playbackProgress
        }
        
    var memo: VoiceMemo
    var editedTitle: String
    var editedText: String
    var transcription: String = "AI文字起こしを開始するには、以下のボタンを押してください。"
    var isTranscribing = false
    var isAppleTranscribing = false
    var appleTranscription: String = "文字起こしを開始するには、以下のボタンを押してください。"
    var currentTranscriptionDisplay: TranscriptionDisplayMode = .apple
    var showingTitleEditModal = false
    var isPlaying = false
    var showingShareSheet = false
    var showingSaveAlert = false
    var showingFillerWordPreview = false
    var showingMoreMenu = false
    var fillerWordResult: FillerWordRemovalResult?
    var backgroundTranscriptionState: BackgroundTranscriptionState = .idle
    var backgroundProgress: CustomTranscriptionProgress = CustomTranscriptionProgress(
      currentSegment: 0,
      totalSegments: 0,
      processedDuration: 0,
      totalDuration: 0,
      transcribedText: ""
    )
    var additionalRecorderState: AdditionalRecorderState = AdditionalRecorderState()
    var playbackProgress: PlaybackProgress? = nil
    
    init(memo: VoiceMemo) {
      self.memo = memo
      self.editedTitle = memo.title
      self.editedText = memo.text
      self.transcription = memo.aiTranscriptionText.isEmpty ? "AI文字起こしを開始するには、以下のボタンを押してください。" : memo.aiTranscriptionText
      // Apple文字起こしは現在textフィールドに保存されているので、それを表示
      self.appleTranscription = memo.text.isEmpty ? "文字起こしを開始するには、以下のボタンを押してください。" : memo.text
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

  struct CustomTranscriptionProgress: Equatable {
    let currentSegment: Int
    let totalSegments: Int
    let processedDuration: TimeInterval
    let totalDuration: TimeInterval
    let transcribedText: String
    
    var percentage: Double {
      guard totalSegments > 0 else { return 0 }
      return Double(currentSegment) / Double(totalSegments)
    }
  }

  enum Action: ViewAction, BindableAction {
    case binding(BindingAction<State>)
    case transcriptionCompleted(String)
    case transcriptionFailed(String)
    case appleTranscriptionCompleted(String)
    case appleTranscriptionFailed(String)
    case backgroundTranscriptionStateChanged(BackgroundTranscriptionState)
    case backgroundProgressUpdated(CustomTranscriptionProgress)
    case additionalRecorderStateChanged(AdditionalRecorderState)
    case fillerWordResultReceived(FillerWordRemovalResult?)
    case memoUpdated(VoiceMemo)
    case playbackProgressUpdated(PlaybackProgress)
    case view(View)

    enum View {
      case onAppear
      case onDisappear
      case togglePlayback
      case startTranscription
      case startAppleTranscription
      case startBackgroundTranscription
      case pauseBackgroundTranscription
      case resumeBackgroundTranscription
      case toggleAdditionalRecording
      case changeTranscriptionDisplay(TranscriptionDisplayMode)
      case showTitleEditModal
      case saveTitleChanges(String)
      case showMoreMenu
      case shareButtonTapped
      case previewFillerWordRemoval
      case applyFillerWordRemoval
    }
  }

  @Dependency(\.voiceMemoController) var voiceMemoController
  @Dependency(\.audioRecorder) var audioRecorder
  @Dependency(\.audioPlayerClient) var audioPlayerClient
  @Dependency(\.continuousClock) var clock
  @Dependency(\.speechRecognitionManager) var speechRecognitionManager

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
          if state.isPlaying {
            return .run { [memoId = state.memo.id] send in
              // UUIDから音声ファイルパスを生成
              let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
              let voiceRecordingsPath = documentsDirectory.appendingPathComponent("VoiceRecordings")
              let filename = "recording-\(memoId.uuidString).m4a"
              let filePath = voiceRecordingsPath.appendingPathComponent(filename).path
              
              await audioPlayerClient.startPlayback(filePath)
              
              // プログレスを監視
              for await progress in await audioPlayerClient.observePlaybackProgress() {
                await send(.playbackProgressUpdated(progress))
              }
              
              // 再生が終了したら状態をリセット
              await send(.playbackProgressUpdated(PlaybackProgress(currentTime: 0, duration: 0)))
            }
          } else {
            state.playbackProgress = nil
            return .run { _ in
              await audioPlayerClient.stopPlayback()
            }
          }
          
        case .startTranscription:
          state.isTranscribing = true
          return .run { [memo = state.memo] send in
            do {
              let text = try await transcribeAudio(memo: memo)
              await send(.transcriptionCompleted(text))
            } catch {
              await send(.transcriptionFailed(error.localizedDescription))
            }
          }
          
        case .startAppleTranscription:
          state.isAppleTranscribing = true
          return .run { [memo = state.memo] send in
            do {
              let audioURL = getAudioURL(for: memo)
              let text = try await speechRecognitionManager.transcribeAudioFile(at: audioURL)
              await send(.appleTranscriptionCompleted(text))
            } catch {
              await send(.appleTranscriptionFailed(error.localizedDescription))
            }
          }
          
        case .startBackgroundTranscription:
          // Background transcription functionality removed
          return .none
          
        case .pauseBackgroundTranscription:
          // Pause functionality removed
          return .none
          
        case .resumeBackgroundTranscription:
          // Resume functionality removed
          return .none
          
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
          
        case let .changeTranscriptionDisplay(mode):
          state.currentTranscriptionDisplay = mode
          return .none
          
        case .showTitleEditModal:
          state.showingTitleEditModal = true
          return .none
          
        case let .saveTitleChanges(newTitle):
          state.showingTitleEditModal = false
          state.editedTitle = newTitle.isEmpty ? "無題" : newTitle
          return .run { [memo = state.memo, title = newTitle.isEmpty ? "無題" : newTitle] send in
            let success = voiceMemoController.updateVoiceMemo(
              id: memo.id,
              title: title,
              text: nil,  // タイトルのみ更新
              aiTranscriptionText: nil
            )
            if success {
              let updatedMemo = voiceMemoController.fetchVoiceMemo(id: memo.id)
              await send(.memoUpdated(updatedMemo ?? memo))
            }
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
          
        }
        
      case let .transcriptionCompleted(text):
        state.transcription = text
        state.isTranscribing = false
        // AI文字起こしテキストを別フィールドに保存
        return .run { [memo = state.memo, title = state.editedTitle] send in
          let success = voiceMemoController.updateVoiceMemo(
            id: memo.id,
            title: title.isEmpty ? "無題" : title,
            text: nil,  // リアルタイム文字起こしは変更しない
            aiTranscriptionText: text  // AI文字起こしとして保存
          )
          if success {
            let updatedMemo = voiceMemoController.fetchVoiceMemo(id: memo.id)
            await send(.memoUpdated(updatedMemo ?? memo))
          }
        }
        
      case let .transcriptionFailed(error):
        state.transcription = "AI文字起こし中にエラーが発生しました: \(error)"
        state.isTranscribing = false
        return .none
        
      case let .appleTranscriptionCompleted(text):
        state.appleTranscription = text
        state.isAppleTranscribing = false
        // Apple文字起こし結果をtextフィールドに保存（上書き）
        return .run { [memo = state.memo, title = state.editedTitle] send in
          let success = voiceMemoController.updateVoiceMemo(
            id: memo.id,
            title: title.isEmpty ? "無題" : title,
            text: text,  // Apple文字起こし結果でtextフィールドを更新
            aiTranscriptionText: nil  // AI文字起こしは変更しない
          )
          if success {
            let updatedMemo = voiceMemoController.fetchVoiceMemo(id: memo.id)
            await send(.memoUpdated(updatedMemo ?? memo))
          }
        }
        
      case let .appleTranscriptionFailed(error):
        state.appleTranscription = "Apple文字起こし中にエラーが発生しました: \(error)"
        state.isAppleTranscribing = false
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
        
      case let .playbackProgressUpdated(progress):
        state.playbackProgress = progress
        if progress.currentTime == 0 && progress.duration == 0 {
          state.isPlaying = false
        }
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


private enum AudioRecorderKey: DependencyKey {
  static let liveValue = AudioRecorder()
}

private enum SpeechRecognitionManagerKey: DependencyKey {
  static let liveValue = SpeechRecognitionManager()
}

extension DependencyValues {
  var voiceMemoController: VoiceMemoController {
    get { self[VoiceMemoControllerKey.self] }
    set { self[VoiceMemoControllerKey.self] = newValue }
  }
  
  
  var audioRecorder: AudioRecorder {
    get { self[AudioRecorderKey.self] }
    set { self[AudioRecorderKey.self] = newValue }
  }
  
  var speechRecognitionManager: SpeechRecognitionManager {
    get { self[SpeechRecognitionManagerKey.self] }
    set { self[SpeechRecognitionManagerKey.self] = newValue }
  }
}

// MARK: - View
@ViewAction(for: VoiceMemoDetailFeature.self)
struct VoiceMemoDetailView: View {
  @Bindable var store: StoreOf<VoiceMemoDetailFeature>
  private let onMemoUpdated: (() -> Void)?
  @State private var showingFileInfo = false
  @StateObject private var adManager: InterstitialAdManager
  @Environment(\.admobConfig) private var admobConfig
  
  init(store: StoreOf<VoiceMemoDetailFeature>, admobKey: String, onMemoUpdated: (() -> Void)? = nil) {
    print("🏗️ VoiceMemoDetailView init - AdMob Key: \(admobKey)")
    self.store = store
    self.onMemoUpdated = onMemoUpdated
    self._adManager = StateObject(wrappedValue: InterstitialAdManager(adUnitID: admobKey))
  }
  
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // タイトルセクション
        titleSection()
        
        // 統合文字起こし結果セクション
        unifiedTranscriptionSection()
        
        // 追加録音セグメント表示
        if !store.memo.segments.isEmpty {
          segmentsSection()
        }
        
        // メインアクションボタン
        actionButtonsSection()
        
        // バナー広告
        bannerAdSection()
      }
      .padding()
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { showingFileInfo = true }) {
          Image(systemName: "info.circle")
        }
      }
    }
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
    .actionSheet(isPresented: $store.showingMoreMenu) {
      ActionSheet(
        title: Text("共有"),
        buttons: createMoreMenuButtons()
      )
    }
    .sheet(isPresented: $showingFileInfo) {
      FileInfoView(memo: store.memo, onDismiss: { showingFileInfo = false })
    }
    .sheet(isPresented: $store.showingTitleEditModal) {
      TitleEditModal(
        title: store.editedTitle,
        onSave: { newTitle in
          send(.saveTitleChanges(newTitle))
        },
        onCancel: {
          store.showingTitleEditModal = false
        }
      )
    }
  }
  
  // MARK: - View Components
  
  private func titleSection() -> some View {
    VStack(spacing: 8) {
      HStack {
        // タイトル表示
        Text(store.editedTitle)
          .font(.largeTitle)
          .fontWeight(.bold)
          .frame(maxWidth: .infinity)
          .multilineTextAlignment(.center)
        
        // 編集ボタン
        Button(action: { send(.showTitleEditModal) }) {
          Image(systemName: "pencil.circle")
            .foregroundColor(.blue)
            .font(.title2)
        }
      }
    }
    .padding(.top)
  }
  
  private func unifiedTranscriptionSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      // セクションヘッダーとプルダウン切替
      HStack {
        Text("文字起こし結果")
          .font(.headline)
        
        Spacer()
        
        // プルダウン形式の表示切替
        Menu {
          ForEach(TranscriptionDisplayMode.allCases, id: \.self) { mode in
            Button(action: {
              send(.changeTranscriptionDisplay(mode))
            }) {
              HStack {
                Text(mode.rawValue)
                if store.currentTranscriptionDisplay == mode {
                  Spacer()
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          HStack {
            Text(store.currentTranscriptionDisplay.rawValue)
            Image(systemName: "chevron.down")
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(Color(.systemGray5))
          .foregroundColor(.primary)
          .cornerRadius(8)
        }
      }
      
      // 文字起こし実行ボタン（常に上部に表示）
      getCurrentModeButton()
      
      // 文字起こし結果表示とコピーボタン
      VStack(spacing: 8) {
        let transcriptionText = getCurrentTranscriptionText()
        let hasResult = !transcriptionText.contains("文字起こしを開始するには")
        
        // 結果表示
        Text(transcriptionText)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.systemGray6))
          .cornerRadius(8)
          .foregroundColor(hasResult ? .primary : .secondary)
        
        // コピーボタン（結果がある場合のみ表示）
        if hasResult {
          Button(action: {
            UIPasteboard.general.string = transcriptionText
          }) {
            HStack {
              Image(systemName: "doc.on.doc")
              Text("文字起こし結果をコピー")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
          }
        }
      }
    }
  }
  
  // MARK: - Helper Functions for Unified Transcription
  
  private func getCurrentTranscriptionText() -> String {
    switch store.currentTranscriptionDisplay {
    case .apple:
      return store.appleTranscription
    case .ai:
      return store.transcription
    }
  }
  
  @ViewBuilder
  private func getCurrentModeButton() -> some View {
    switch store.currentTranscriptionDisplay {
    case .apple:
      Button(action: { send(.startAppleTranscription) }) {
        HStack {
          Image(systemName: "waveform")
          Text(store.isAppleTranscribing ? "変換中..." : "文字起こし実行")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(store.isAppleTranscribing ? Color.gray : Color.blue)
        .foregroundColor(.white)
        .cornerRadius(8)
      }
      .disabled(store.isAppleTranscribing)
    case .ai:
      Button(action: {
        // AI文字起こし前に広告を表示
        adManager.showInterstitialAd {
          // 広告終了後にAI文字起こしを開始
          send(.startTranscription)
        }
      }) {
        HStack {
          Image(systemName: "brain")
          Text(store.isTranscribing ? "変換中..." : "AI文字起こし実行")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(store.isTranscribing ? Color.gray : Color.purple)
        .foregroundColor(.white)
        .cornerRadius(8)
      }
      .disabled(store.isTranscribing)
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
  
  
  private func actionButtonsSection() -> some View {
    VStack(spacing: 12) {
      // プログレス表示（常時表示）
      VStack(spacing: 8) {
        // 再生時間表示
        HStack {
          Text(formatTime(store.playbackProgress?.currentTime ?? 0))
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Text(formatTime(store.playbackProgress?.duration ?? 0))
            .font(.caption)
            .foregroundColor(.secondary)
        }
        
        // プログレスバー
        ProgressView(value: store.playbackProgress?.progress ?? 0)
          .progressViewStyle(LinearProgressViewStyle(tint: .green))
          .frame(height: 4)
        
        // 音声波形アニメーション
        HStack(spacing: 2) {
          ForEach(0..<10) { index in
            RoundedRectangle(cornerRadius: 1)
              .fill(Color.green)
              .frame(width: 2, height: store.isPlaying ? getRandomHeight() : 4)
              .animation(
                store.isPlaying ?
                  Animation.easeInOut(duration: Double.random(in: 0.3...0.8))
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.05) :
                  .default,
                value: store.isPlaying
              )
          }
        }
        .frame(height: 20)
      }
      .padding()
      .background(Color(.systemGray6))
      .cornerRadius(12)
      
      // 再生ボタン
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
      
      // その他メニューボタン
      Button(action: { send(.shareButtonTapped) }) {
        HStack {
          Image(systemName: "square.and.arrow.up")
          Text("共有")
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
    
    // 共有ボタン
    buttons.append(.default(Text("📤 共有")) {
      send(.shareButtonTapped)
    })
    
    // キャンセルボタン
    buttons.append(.cancel(Text("キャンセル")))
    
    return buttons
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
  
  private func getRandomHeight() -> CGFloat {
    return CGFloat.random(in: 4...20)
  }
  
  private func bannerAdSection() -> some View {
    VStack {
      Text("広告")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 8)
      
      BannerAdView(adUnitID: admobConfig.bannerAdUnitID)
        .frame(width: 320, height: 50)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
  }
}
