//
//  AudioRecorder.swift
//  voicedocs
//
//

import Foundation
import AVFoundation
import Combine
import UIKit

enum RecordingQuality: CaseIterable {
    case standard
    case high

    var settings: [String: Any] {
        switch self {
        case .standard:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
        case .high:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
                AVEncoderBitRateKey: 128000
            ]
        }
    }

    var displayName: String {
        switch self {
        case .standard:
            return "標準品質"
        case .high:
            return "高品質"
        }
    }
}

enum RecordingMode {
    case newRecording
    case additionalRecording(memoId: UUID)
}

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession!
    private var audioFileURL: URL?
    private var recordingTimer: Timer?
    private var startTime: Date?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var recordingMode: RecordingMode = .newRecording
    private var segmentIndex: Int = 0
    private let voiceMemoController = VoiceMemoController.shared

    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var recordingQuality: RecordingQuality = .high
    @Published var lastRecordedFileURL: URL?
    @Published var lastRecordedMemoId: UUID?

    override init() {
        super.init()
        setupRecordingSession()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupRecordingSession() {
        recordingSession = AVAudioSession.sharedInstance()

        do {
            // ここではカテゴリの設定のみ行い、アクティブ化は録音開始時に行う
            try recordingSession.setCategory(.playAndRecord,
                                           mode: .default,
                                           options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        } catch {
            // セッション設定に失敗した場合はデフォルト設定を使用
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // 割り込み処理の追加
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            if isRecording {
                audioRecorder?.pause()
            }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && isRecording {
                audioRecorder?.record()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleAppWillResignActive() {
        if isRecording {
            startBackgroundTask()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        endBackgroundTask()
    }

    private func startBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "VoiceRecording") {
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    func startRecording() {
        guard !isRecording else {
            return
        }

        requestPermissions { [weak self] granted in
            guard granted else {
                return
            }

            DispatchQueue.main.async {
                self?.performStartRecording()
            }
        }
    }

    func startAdditionalRecording(for memoId: UUID) {
        guard !isRecording else { return }

        recordingMode = .additionalRecording(memoId: memoId)
        let segments = voiceMemoController.getSegmentsForMemo(memoId: memoId)
        segmentIndex = segments.count

        requestPermissions { [weak self] granted in
            guard granted else {
                return
            }

            DispatchQueue.main.async {
                self?.performStartRecording()
            }
        }
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            completion(granted)
        }
    }

    private func performStartRecording() {

        // ディレクトリの準備
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let voiceRecordingsPath = documentsPath.appendingPathComponent("VoiceRecordings")

        do {
            if !FileManager.default.fileExists(atPath: voiceRecordingsPath.path) {
                try FileManager.default.createDirectory(at: voiceRecordingsPath,
                                                       withIntermediateDirectories: true,
                                                       attributes: nil)
            }
        } catch {
            return
        }

        // ファイルパスの設定
        let audioFilename: URL
        switch recordingMode {
        case .newRecording:
            audioFilename = voiceRecordingsPath.appendingPathComponent("\(UUID().uuidString).m4a")
        case .additionalRecording(let memoId):
            let segmentPath = voiceMemoController.generateSegmentFilePath(memoId: memoId, segmentIndex: segmentIndex)
            audioFilename = URL(fileURLWithPath: segmentPath)

            // セグメントファイルのディレクトリも確認
            let segmentDir = audioFilename.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: segmentDir.path) {
                try? FileManager.default.createDirectory(at: segmentDir,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
            }
        }

        let settings = recordingQuality.settings

        do {
            // オーディオセッションをアクティブ化
            try recordingSession.setActive(true, options: [])

            // レコーダーの初期化
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            // 録音の準備と開始
            let prepared = audioRecorder?.prepareToRecord() ?? false
            guard prepared else {
                try recordingSession.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }

            let success = audioRecorder?.record() ?? false
            guard success else {
                try recordingSession.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }

            audioFileURL = audioFilename
            isRecording = true
            startTime = Date()
            recordingDuration = 0

            startRecordingTimer()

        } catch {
            // エラー時のクリーンアップ
            audioRecorder = nil
            audioFileURL = nil
            isRecording = false
            try? recordingSession.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func stopRecording() {
        guard isRecording else {
            return
        }

        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        endBackgroundTask()

        // 録音完了時にコールバックを呼び出す
        if let audioFileURL = audioFileURL {
            // ファイルが実際に存在するか確認
            if FileManager.default.fileExists(atPath: audioFileURL.path) {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: audioFileURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0

                    if fileSize > 0 {
                        // 録音したファイルのURLを保存
                        lastRecordedFileURL = audioFileURL
                        saveRecording(url: audioFileURL, duration: recordingDuration)
                    } else {
                        lastRecordedFileURL = nil
                    }
                } catch {
                    // ファイル属性の取得に失敗した場合はスキップ
                }
            }
        }

        // セッションを非アクティブ化
        do {
            try recordingSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // セッション非アクティブ化に失敗した場合はスキップ
        }
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateRecordingProgress()
        }
    }

    private func updateRecordingProgress() {
        guard let startTime = startTime else {
            return
        }

        let newDuration = Date().timeIntervalSince(startTime)

        // メインスレッドでUI更新を確実に行う
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.recordingDuration = newDuration

            // 音声レベルを更新
            self.audioRecorder?.updateMeters()
            if let recorder = self.audioRecorder {
                let normalizedLevel = pow(10, recorder.averagePower(forChannel: 0) / 20)
                self.audioLevel = Float(normalizedLevel)
            }
        }
    }

    private func saveRecording(url: URL, duration: TimeInterval) {
        switch recordingMode {
        case .newRecording:
            // 新しいメモとして保存
            let memoId = UUID()
            
            // ファイルを正しい場所に移動（UUIDベースのファイル名）
            let newFileName = "recording-\(memoId.uuidString).m4a"
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let voiceRecordingsPath = documentsDirectory.appendingPathComponent("VoiceRecordings")
            let newFileURL = voiceRecordingsPath.appendingPathComponent(newFileName)
            
            do {
                // 既存のファイルがあれば削除
                if FileManager.default.fileExists(atPath: newFileURL.path) {
                    try FileManager.default.removeItem(at: newFileURL)
                }
                // ファイルを移動
                try FileManager.default.moveItem(at: url, to: newFileURL)
            } catch {
                print("Failed to move recording file: \(error)")
            }
            
            voiceMemoController.saveVoiceMemo(
                title: "録音 \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
                text: "", // 音声認識結果は別途設定
                filePath: nil // filePathは使用しない
            )
            
            // 保存されたメモのIDを記録（文字起こし用）
            lastRecordedMemoId = memoId

        case .additionalRecording(let memoId):
            // セグメントとして追加
            let segment = AudioSegment(
                filePath: url.path,
                startTime: 0, // ここでは仮の値、実際は別途計算
                duration: duration
            )

            _ = voiceMemoController.addSegmentToMemo(memoId: memoId, segment: segment)
            lastRecordedMemoId = memoId
        }

        // モードをリセット
        recordingMode = .newRecording
        segmentIndex = 0
    }
    
    private func getLatestMemoId() -> UUID? {
        // 最新のメモを取得してIDを返す
        let memos = voiceMemoController.fetchVoiceMemos()
        return memos.first?.id
    }

    func setRecordingQuality(_ quality: RecordingQuality) {
        guard !isRecording else {
            return
        }
        recordingQuality = quality
    }

    func getRemainingBackgroundTime() -> TimeInterval {
        return UIApplication.shared.backgroundTimeRemaining
    }

    // 追加録音モードかどうかを確認
    func isAdditionalRecordingMode() -> Bool {
        if case .additionalRecording = recordingMode {
            return true
        }
        return false
    }

    // 現在の録音モードを取得
    func getCurrentRecordingMode() -> RecordingMode {
        return recordingMode
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.endBackgroundTask()
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.endBackgroundTask()
        }
    }
}
