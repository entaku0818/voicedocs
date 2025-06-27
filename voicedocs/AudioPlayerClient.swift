import Foundation
import AVFoundation
import ComposableArchitecture

// MARK: - AudioPlayerClient Protocol
struct AudioPlayerClient {
  var startPlayback: @Sendable (String) async -> Void
  var stopPlayback: @Sendable () async -> Void
  var isPlaying: @Sendable () async -> Bool
  var getCurrentTime: @Sendable () async -> TimeInterval
  var getDuration: @Sendable () async -> TimeInterval
  var observePlaybackProgress: @Sendable () async -> AsyncStream<PlaybackProgress>
}

struct PlaybackProgress: Equatable {
  let currentTime: TimeInterval
  let duration: TimeInterval
  
  var progress: Double {
    guard duration > 0 else { return 0 }
    return currentTime / duration
  }
}

// MARK: - Live Implementation
extension AudioPlayerClient {
  static let live = Self(
    startPlayback: { filePath in
      await AudioPlayerManager.shared.startPlayback(filePath: filePath)
    },
    stopPlayback: {
      await AudioPlayerManager.shared.stopPlayback()
    },
    isPlaying: {
      await AudioPlayerManager.shared.isPlaying
    },
    getCurrentTime: {
      await AudioPlayerManager.shared.getCurrentTime()
    },
    getDuration: {
      await AudioPlayerManager.shared.getDuration()
    },
    observePlaybackProgress: {
      await AudioPlayerManager.shared.playbackProgressStream()
    }
  )
}

// MARK: - Test Implementation
extension AudioPlayerClient {
  static let test = Self(
    startPlayback: { _ in },
    stopPlayback: { },
    isPlaying: { false },
    getCurrentTime: { 0 },
    getDuration: { 0 },
    observePlaybackProgress: { AsyncStream { _ in } }
  )
}

// MARK: - AudioPlayerManager
@MainActor
class AudioPlayerManager: ObservableObject {
  static let shared = AudioPlayerManager()

  @Published private var _isPlaying = false
  private var player: AVPlayer?
  private var playerItem: AVPlayerItem?
  private var timeObserver: Any?
  nonisolated(unsafe) private var progressContinuation: AsyncStream<PlaybackProgress>.Continuation?

  var isPlaying: Bool {
    _isPlaying
  }
  
  func getCurrentTime() -> TimeInterval {
    guard let player = player else { return 0 }
    return player.currentTime().seconds
  }
  
  func getDuration() -> TimeInterval {
    guard let item = playerItem else { return 0 }
    return item.duration.seconds
  }
  
  func playbackProgressStream() -> AsyncStream<PlaybackProgress> {
    AsyncStream { continuation in
      self.progressContinuation = continuation
      
      continuation.onTermination = { _ in
        self.progressContinuation = nil
      }
    }
  }

  func startPlayback(filePath: String) async {
    // 既存の再生を停止
    stopPlayback()

    guard !filePath.isEmpty else {
      return
    }

    // VoiceRecordingsディレクトリからファイルを取得
    let audioURL = getAudioURL(for: filePath)

    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      return
    }

    // ファイルサイズを確認
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
      let fileSize = attributes[.size] as? Int64 ?? 0

      if fileSize == 0 {
        return
      }
    } catch {
      return
    }

    do {
      // AVAudioSessionを再生用に設定
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)

      // AVPlayerItemを作成
      playerItem = AVPlayerItem(url: audioURL)

      // AVPlayerを作成して再生開始
      player = AVPlayer(playerItem: playerItem)
      player?.play()
      _isPlaying = true

      // 再生状態を監視
      addPeriodicTimeObserver()

      // 再生終了を監視
      NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: playerItem,
        queue: .main
      ) { [weak self] _ in
        self?.stopPlayback()
      }

      // エラーを監視
      NotificationCenter.default.addObserver(
        forName: .AVPlayerItemFailedToPlayToEndTime,
        object: playerItem,
        queue: .main
      ) { [weak self] notification in
        self?.stopPlayback()
      }

    } catch {
      _isPlaying = false
    }
  }

  func stopPlayback() {
    // タイムオブザーバーを削除
    if let timeObserver = timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }

    player?.pause()
    player = nil
    playerItem = nil
    _isPlaying = false
    
    // プログレスストリームを終了
    progressContinuation?.finish()
    progressContinuation = nil

    // NotificationCenterのオブザーバーを削除
    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)

    // AVAudioSessionを非アクティブにする（録音を可能にするため）
    do {
      let session = AVAudioSession.sharedInstance()
      // setActive(false)の前に少し待機
      Thread.sleep(forTimeInterval: 0.1)
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // セッション非アクティブ化に失敗した場合はスキップ
    }
  }

  private func addPeriodicTimeObserver() {
    let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      guard let self = self, let player = self.player, let item = self.playerItem else { return }

      // 再生状態を確認して異常を検出
      if player.rate == 0 && self._isPlaying {
        // 再生が予期せず停止した場合の処理
      }
      
      // プログレス情報を送信
      let currentTime = time.seconds
      let duration = item.duration.seconds
      
      if currentTime.isFinite && duration.isFinite && duration > 0 {
        let progress = PlaybackProgress(
          currentTime: currentTime,
          duration: duration
        )
        self.progressContinuation?.yield(progress)
      }
    }
  }

  private func getAudioURL(for filePath: String) -> URL {
    // ファイルパスがフルパスの場合はそのまま使用
    if filePath.hasPrefix("/") {
      return URL(fileURLWithPath: filePath)
    }

    // ファイル名のみの場合はVoiceRecordingsディレクトリから取得
    guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      fatalError("Documents directory not found")
    }

    let voiceRecordingsPath = documentsDirectory.appendingPathComponent("VoiceRecordings")
    let filePathComponent = (filePath as NSString).lastPathComponent
    return voiceRecordingsPath.appendingPathComponent(filePathComponent)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

// MARK: - Dependency Key
private enum AudioPlayerClientKey: DependencyKey {
  static let liveValue = AudioPlayerClient.live
  static let testValue = AudioPlayerClient.test
}

extension DependencyValues {
  var audioPlayerClient: AudioPlayerClient {
    get { self[AudioPlayerClientKey.self] }
    set { self[AudioPlayerClientKey.self] = newValue }
  }
}
