//
//  AudioRecorder.swift
//  voicedocs
//
//  Created by Claude on 2025/6/12.
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
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
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

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession!
    private var audioFileURL: URL?
    private var recordingTimer: Timer?
    private var startTime: Date?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var recordingQuality: RecordingQuality = .high
    
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
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try recordingSession.setActive(true)
        } catch {
            print("Failed to set up recording session: \(error)")
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
        guard !isRecording else { return }
        
        requestPermissions { [weak self] granted in
            guard granted else {
                print("Recording permission not granted")
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
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
        
        let settings = recordingQuality.settings
        
        do {
            try recordingSession.setActive(true)
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            // 長時間録音に対応するための設定
            audioRecorder?.prepareToRecord()
            let success = audioRecorder?.record() ?? false
            
            guard success else {
                print("Failed to start recording")
                return
            }
            
            audioFileURL = audioFilename
            isRecording = true
            startTime = Date()
            recordingDuration = 0
            
            startRecordingTimer()
            
        } catch {
            print("Could not start recording: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        endBackgroundTask()
        
        // 録音完了時にコールバックを呼び出す
        if let audioFileURL = audioFileURL {
            saveRecording(url: audioFileURL, duration: recordingDuration)
        }
        
        do {
            try recordingSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateRecordingProgress()
        }
    }
    
    private func updateRecordingProgress() {
        guard let startTime = startTime else { return }
        
        recordingDuration = Date().timeIntervalSince(startTime)
        
        // 音声レベルを更新
        audioRecorder?.updateMeters()
        if let recorder = audioRecorder {
            let normalizedLevel = pow(10, recorder.averagePower(forChannel: 0) / 20)
            audioLevel = Float(normalizedLevel)
        }
    }
    
    private func saveRecording(url: URL, duration: TimeInterval) {
        // VoiceMemoControllerを使用してCore Dataに保存
        VoiceMemoController.shared.saveVoiceMemo(
            title: "録音 \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            text: "", // 音声認識結果は別途設定
            filePath: url.path
        )
    }
    
    func setRecordingQuality(_ quality: RecordingQuality) {
        guard !isRecording else {
            print("Cannot change quality while recording")
            return
        }
        recordingQuality = quality
    }
    
    func getRemainingBackgroundTime() -> TimeInterval {
        return UIApplication.shared.backgroundTimeRemaining
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.endBackgroundTask()
        }
        
        if !flag {
            print("Recording failed")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.endBackgroundTask()
        }
        
        if let error = error {
            print("Recording error: \(error)")
        }
    }
}