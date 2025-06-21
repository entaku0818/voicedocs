import Foundation
import AVFoundation
import ComposableArchitecture

// MARK: - AudioPlayerClient Protocol
struct AudioPlayerClient {
  var startPlayback: @Sendable (String) async -> Void
  var stopPlayback: @Sendable () async -> Void
  var isPlaying: @Sendable () async -> Bool
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
    }
  )
}

// MARK: - Test Implementation
extension AudioPlayerClient {
  static let test = Self(
    startPlayback: { _ in },
    stopPlayback: { },
    isPlaying: { false }
  )
}

// MARK: - AudioPlayerManager
@MainActor
class AudioPlayerManager: ObservableObject {
  static let shared = AudioPlayerManager()
  
  @Published private var _isPlaying = false
  private var player: AVPlayer?
  
  private init() {}
  
  var isPlaying: Bool {
    _isPlaying
  }
  
  func startPlayback(filePath: String) async {
    stopPlayback()
    
    guard !filePath.isEmpty else { return }
    
    // VoiceRecordingsディレクトリからファイルを取得
    let audioURL = getAudioURL(for: filePath)
    
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      print("Audio file not found: \(audioURL.path)")
      return
    }
    
    do {
      // AVAudioSessionを設定
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      
      // AVPlayerを作成して再生開始
      player = AVPlayer(url: audioURL)
      player?.play()
      _isPlaying = true
      
      // 再生終了を監視
      NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: player?.currentItem,
        queue: .main
      ) { [weak self] _ in
        self?.stopPlayback()
      }
      
    } catch {
      print("Failed to start audio playback: \(error)")
    }
  }
  
  func stopPlayback() {
    player?.pause()
    player = nil
    _isPlaying = false
    
    // NotificationCenterのオブザーバーを削除
    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    
    // AVAudioSessionを非アクティブにする
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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