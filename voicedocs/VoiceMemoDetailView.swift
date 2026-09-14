import SwiftUI
import ComposableArchitecture
import AVFoundation
import GoogleMobileAds


@Reducer
struct VoiceMemoDetailFeature {
  @ObservableState
    struct State: Equatable {
        static func == (lhs: VoiceMemoDetailFeature.State, rhs: VoiceMemoDetailFeature.State) -> Bool {
            return lhs.memo.id == rhs.memo.id &&
                   lhs.editedTitle == rhs.editedTitle &&
                   lhs.editedText == rhs.editedText &&
                   lhs.isTranscribing == rhs.isTranscribing &&
                   lhs.transcription == rhs.transcription &&
                   lhs.showingTitleEditModal == rhs.showingTitleEditModal &&
                   lhs.isPlaying == rhs.isPlaying &&
                   lhs.showingShareSheet == rhs.showingShareSheet &&
                   lhs.showingSaveAlert == rhs.showingSaveAlert &&
                   lhs.showingFillerWordPreview == rhs.showingFillerWordPreview &&
                   lhs.showingMoreMenu == rhs.showingMoreMenu &&
                   lhs.backgroundTranscriptionState == rhs.backgroundTranscriptionState &&
                   lhs.backgroundProgress == rhs.backgroundProgress &&
                   lhs.additionalRecorderState == rhs.additionalRecorderState &&
                   lhs.playbackProgress == rhs.playbackProgress &&
                   lhs.isConcatenating == rhs.isConcatenating &&
                   lhs.concatenationProgress == rhs.concatenationProgress &&
                   lhs.concatenatedAudioURL == rhs.concatenatedAudioURL &&
                   lhs.concatenationError == rhs.concatenationError &&
                   lhs.aiNote == rhs.aiNote
        }

    var memo: VoiceMemo
    var editedTitle: String
    var editedText: String
    var isTranscribing = false
    var transcription: String = "文字起こしを開始するには、以下のボタンを押してください。"
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
    var isConcatenating = false
    var concatenationProgress: Double = 0
    var concatenatedAudioURL: URL? = nil
    var concatenationError: String? = nil
    var aiNote = AINoteFeature.State()

    init(memo: VoiceMemo) {
      self.memo = memo
      self.editedTitle = memo.title
      self.editedText = memo.text
      self.transcription = memo.text.isEmpty ? "文字起こしを開始するには、以下のボタンを押してください。" : memo.text
      self.aiNote = AINoteFeature.State(
        transcriptionText: memo.text,
        savedNoteText: memo.aiTranscriptionText
      )
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
    case backgroundTranscriptionStateChanged(BackgroundTranscriptionState)
    case backgroundProgressUpdated(CustomTranscriptionProgress)
    case additionalRecorderStateChanged(AdditionalRecorderState)
    case fillerWordResultReceived(FillerWordRemovalResult?)
    case memoUpdated(VoiceMemo)
    case playbackProgressUpdated(PlaybackProgress)
    case concatenationProgressUpdated(Double)
    case concatenationCompleted(URL)
    case concatenationFailed(String)
    case aiNote(AINoteFeature.Action)
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
      case showTitleEditModal
      case saveTitleChanges(String)
      case showMoreMenu
      case shareButtonTapped
      case previewFillerWordRemoval
      case applyFillerWordRemoval
      case startConcatenation
    }
  }

  @Dependency(\.voiceMemoController) var voiceMemoController
  @Dependency(\.audioRecorder) var audioRecorder
  @Dependency(\.audioPlayerClient) var audioPlayerClient
  @Dependency(\.continuousClock) var clock
  @Dependency(\.speechRecognitionManager) var speechRecognitionManager

  var body: some Reducer<State, Action> {
    BindingReducer()
    Scope(state: \.aiNote, action: \.aiNote) {
      AINoteFeature()
    }
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
          state.backgroundTranscriptionState = .processing
          return .run { [memo = state.memo] send in
            let audioURL = getAudioURL(for: memo)

            // 進捗監視タスクを開始
            let progressTask = Task {
              while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                let progress = await MainActor.run { speechRecognitionManager.progress }
                await send(.backgroundProgressUpdated(CustomTranscriptionProgress(
                  currentSegment: progress.currentChunk,
                  totalSegments: progress.totalChunks,
                  processedDuration: progress.processedDuration,
                  totalDuration: progress.totalDuration,
                  transcribedText: progress.transcribedText
                )))

                if progress.status == .completed || progress.status == .cancelled {
                  break
                }
              }
            }

            // 文字起こしを実行
            do {
              let text = try await speechRecognitionManager.transcribeLongAudioFile(at: audioURL)
              progressTask.cancel()
              await send(.transcriptionCompleted(text))
            } catch {
              progressTask.cancel()
              await send(.transcriptionFailed(error.localizedDescription))
            }
          }

        case .startBackgroundTranscription:
          // startTranscriptionに統合済み
          return .none

        case .pauseBackgroundTranscription:
          state.backgroundTranscriptionState = .paused
          return .run { _ in
            speechRecognitionManager.pauseTranscription()
          }

        case .resumeBackgroundTranscription:
          state.backgroundTranscriptionState = .processing
          return .run { _ in
            speechRecognitionManager.resumeTranscription()
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

        case .startConcatenation:
          state.isConcatenating = true
          state.concatenationProgress = 0
          state.concatenationError = nil
          return .run { [memoId = state.memo.id] send in
            // 進捗監視タスクを開始
            let service = await AudioConcatenationService()
            let progressTask = Task {
              while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                let progress = await MainActor.run { service.progress }
                await send(.concatenationProgressUpdated(progress))

                if progress >= 1.0 {
                  break
                }
              }
            }

            // セグメント連結を実行
            do {
              let outputURL = try await voiceMemoController.concatenateSegments(memoId: memoId)
              progressTask.cancel()
              await send(.concatenationCompleted(outputURL))
            } catch {
              progressTask.cancel()
              await send(.concatenationFailed(error.localizedDescription))
            }
          }

        }

        
      case let .transcriptionCompleted(text):
        state.transcription = text
        state.isTranscribing = false
        state.aiNote.transcriptionText = text
        // 文字起こし結果をtextフィールドに保存
        return .run { [memo = state.memo, title = state.editedTitle] send in
          let success = voiceMemoController.updateVoiceMemo(
            id: memo.id,
            title: title.isEmpty ? "無題" : title,
            text: text,
            aiTranscriptionText: nil
          )
          if success {
            let updatedMemo = voiceMemoController.fetchVoiceMemo(id: memo.id)
            await send(.memoUpdated(updatedMemo ?? memo))
          }
        }

      case let .transcriptionFailed(error):
        state.transcription = "文字起こし中にエラーが発生しました: \(error)"
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
        state.aiNote.transcriptionText = memo.text
        state.aiNote.savedNoteText = memo.aiTranscriptionText
        return .none

      // AIノートの保存結果を Core Data の aiTranscriptionText に永続化する。
      // 既存の text / title は触らないので、保存済みの文字起こしは壊れない。
      case let .aiNote(.delegate(.saved(noteText))):
        return .run { [memo = state.memo] send in
          let success = voiceMemoController.updateVoiceMemo(
            id: memo.id,
            title: nil,
            text: nil,
            aiTranscriptionText: noteText
          )
          if success {
            let updatedMemo = voiceMemoController.fetchVoiceMemo(id: memo.id)
            await send(.memoUpdated(updatedMemo ?? memo))
          }
        }

      case .aiNote:
        return .none
        
      case let .playbackProgressUpdated(progress):
        state.playbackProgress = progress
        if progress.currentTime == 0 && progress.duration == 0 {
          state.isPlaying = false
        }
        return .none

      case let .concatenationProgressUpdated(progress):
        state.concatenationProgress = progress
        return .none

      case let .concatenationCompleted(url):
        state.isConcatenating = false
        state.concatenationProgress = 1.0
        state.concatenatedAudioURL = url
        state.concatenationError = nil
        return .none

      case let .concatenationFailed(error):
        state.isConcatenating = false
        state.concatenationProgress = 0
        state.concatenationError = error
        return .none
      }
    }
  }
}

// MARK: - Helper Functions
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

  /// AIノート生成の開始に合わせてインタースティシャルを表示する。
  ///
  /// 発火点をここにした理由:
  /// - AIノート生成はユーザーが明示的にボタンを押して起動する重い処理で、
  ///   オンデバイス生成の待ち時間がそのまま広告の尺になる（体験を止めない）。
  /// - 録音中・文字起こし処理中は中核体験なので絶対に出さない（下のガード）。
  ///
  /// 生成自体は非同期に走り続けるので、広告の完了を待つ必要はない（completion は空）。
  /// 実際に出すかどうかの最終判断は `AdPresentationCoordinator`（相互排他 + 表示間隔）が持つ。
  @MainActor
  private func maybeShowInterstitialAd(for status: AINoteFeature.State.Status) {
    guard case .generating = status else { return }

    // 録音中・文字起こし処理中は広告を出さない
    let isTranscriptionRunning: Bool
    switch store.backgroundTranscriptionState {
    case .processing, .paused: isTranscriptionRunning = true
    case .idle, .completed, .failed: isTranscriptionRunning = false
    }
    guard !store.additionalRecorderState.isRecording,
          !store.isTranscribing,
          !isTranscriptionRunning else {
      AppLogger.ads.debug("Interstitial skipped: recording or transcription in progress")
      return
    }

    adManager.showInterstitialAd { }
  }
  
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // タイトルセクション
        titleSection()

        // 動画プレーヤーセクション（動画がある場合）
        if store.memo.hasVideo {
          videoPlayerSection()
        }

        // 統合文字起こし結果セクション
        unifiedTranscriptionSection()

        // AIノートセクション（要約 + アクションアイテム / オンデバイス生成）
        AINoteView(store: store.scope(state: \.aiNote, action: \.aiNote))

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
    .onChange(of: store.aiNote.status) { _, newStatus in
      maybeShowInterstitialAd(for: newStatus)
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

  private func videoPlayerSection() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("動画")
        .font(.headline)
        .foregroundColor(.secondary)

      if let videoURL = store.memo.videoFileURL {
        CustomVideoPlayerView(videoURL: videoURL)
      } else {
        Text("動画ファイルが見つかりません")
          .foregroundColor(.red)
          .font(.caption)
      }
    }
    .padding(.vertical, 8)
  }

  private func unifiedTranscriptionSection() -> some View {
    VStack(alignment: .leading, spacing: 12) {
      // セクションヘッダー
      Text("文字起こし結果")
        .font(.headline)

      // 操作ボタン
      HStack(spacing: 12) {
        // 文字起こし実行ボタン
        Button(action: { send(.startTranscription) }) {
          HStack {
            Image(systemName: "waveform")
            Text(store.isTranscribing ? "変換中..." : "文字起こし実行")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(store.isTranscribing ? Color.gray : Color.blue)
          .foregroundColor(.white)
          .cornerRadius(8)
        }
        .disabled(store.isTranscribing)

        // 一時停止/再開ボタン（処理中のみ表示）
        if store.isTranscribing {
          if store.backgroundTranscriptionState == .paused {
            Button(action: { send(.resumeBackgroundTranscription) }) {
              HStack {
                Image(systemName: "play.fill")
                Text("再開")
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(Color.green)
              .foregroundColor(.white)
              .cornerRadius(8)
            }
          } else {
            Button(action: { send(.pauseBackgroundTranscription) }) {
              HStack {
                Image(systemName: "pause.fill")
                Text("一時停止")
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(Color.orange)
              .foregroundColor(.white)
              .cornerRadius(8)
            }
          }
        }
      }

      // 進捗表示（処理中のみ）
      if store.isTranscribing {
        VStack(alignment: .leading, spacing: 8) {
          // プログレスバー
          ProgressView(value: store.backgroundProgress.percentage)
            .progressViewStyle(LinearProgressViewStyle(tint: .blue))

          // 進捗テキスト
          HStack {
            Text("チャンク \(store.backgroundProgress.currentSegment)/\(store.backgroundProgress.totalSegments)")
              .font(.caption)
              .foregroundColor(.secondary)
            Spacer()
            Text("\(Int(store.backgroundProgress.percentage * 100))%")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          // 処理時間
          if store.backgroundProgress.totalDuration > 0 {
            Text("処理済み: \(formatDuration(store.backgroundProgress.processedDuration)) / \(formatDuration(store.backgroundProgress.totalDuration))")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
      }

      // 文字起こし結果表示とコピーボタン
      VStack(spacing: 8) {
        let hasResult = !store.transcription.contains("文字起こしを開始するには")

        // 結果表示
        Text(store.transcription)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.systemGray6))
          .cornerRadius(8)
          .foregroundColor(hasResult ? .primary : .secondary)

        // コピーボタン（結果がある場合のみ表示）
        if hasResult {
          Button(action: {
            UIPasteboard.general.string = store.transcription
          }) {
            HStack {
              Image(systemName: "doc.on.doc")
              Text("コピー")
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
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
      }

      Text("合計時間: \(formatDuration(store.memo.totalDuration))")
        .font(.caption)
        .foregroundColor(.secondary)

      // 連結機能（セグメントが2つ以上ある場合のみ表示）
      if store.memo.segments.count >= 2 {
        Divider()
          .padding(.vertical, 8)

        if store.isConcatenating {
          // 連結中: 進捗バー表示
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("セグメントを連結中...")
                .font(.subheadline)
              Spacer()
              Text("\(Int(store.concatenationProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            ProgressView(value: store.concatenationProgress)
              .progressViewStyle(LinearProgressViewStyle(tint: .blue))
          }
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(8)
        } else if let _ = store.concatenatedAudioURL {
          // 連結完了: 成功メッセージ
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text("連結完了")
              .font(.subheadline)
          }
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(8)
        } else if let error = store.concatenationError {
          // エラー: エラーメッセージ
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
              Text("連結エラー")
                .font(.subheadline)
            }
            Text(error)
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(8)
        } else {
          // 連結ボタン
          Button {
            send(.startConcatenation)
          } label: {
            HStack {
              Image(systemName: "link")
              Text("セグメントを連結")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
          }
        }
      }
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
          // 再生中はplaybackProgressから、そうでなければtotalDurationを表示
          Text(formatTime(store.playbackProgress?.duration ?? store.memo.totalDuration))
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

    【文字起こし結果】
    \(store.transcription)
    """
    items.append(textContent)

    // 連結ファイルが存在する場合は優先的に共有
    if let concatenatedURL = store.concatenatedAudioURL,
       FileManager.default.fileExists(atPath: concatenatedURL.path) {
      items.append(concatenatedURL)
    } else {
      // 連結ファイルがない場合は個別セグメントファイルを共有
      let filePath = getFilePath(for: store.memo.id)
      if !filePath.isEmpty {
        let fileURL = URL(fileURLWithPath: filePath)
        if FileManager.default.fileExists(atPath: filePath) {
          items.append(fileURL)
        }
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
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
  }
}
