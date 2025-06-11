//
//  AudioRecorder.swift
//  voicedocs
//
//  Created by Claude on 2025/6/12.
//

import Foundation
import AVFoundation
import Combine

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession!
    private var audioFileURL: URL?
    private var recordingTimer: Timer?
    private var startTime: Date?
    
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    
    override init() {
        super.init()
        setupRecordingSession()
    }
    
    private func setupRecordingSession() {
        recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
        } catch {
            print("Failed to set up recording session: \(error)")
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            audioFileURL = audioFilename
            isRecording = true
            startTime = Date()
            recordingDuration = 0
            
            // タイマーを開始して録音時間と音声レベルを更新
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
        
        // 録音完了時にコールバックを呼び出す
        if let audioFileURL = audioFileURL {
            saveRecording(url: audioFileURL, duration: recordingDuration)
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
    
    // MARK: - AVAudioRecorderDelegate
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording failed")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
        }
    }
}