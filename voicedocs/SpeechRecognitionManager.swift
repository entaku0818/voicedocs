//
//  SpeechRecognitionManager.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/01.
//

import Foundation
import Speech
import AVFoundation
import Combine
import UIKit

enum SpeechLanguage: String, CaseIterable {
    case japanese = "ja-JP"
    case english = "en-US"
    
    var displayName: String {
        switch self {
        case .japanese:
            return "日本語"
        case .english:
            return "English"
        }
    }
    
    var locale: Locale {
        return Locale(identifier: self.rawValue)
    }
}

enum SpeechRecognitionError: LocalizedError, Equatable {
    case unavailable
    case unauthorized
    case configurationFailed
    case recognitionFailed(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "音声認識が利用できません"
        case .unauthorized:
            return "音声認識の権限が許可されていません"
        case .configurationFailed:
            return "音声認識の設定に失敗しました"
        case .recognitionFailed(let message):
            return "音声認識エラー: \(message)"
        case .timeout:
            return "音声認識がタイムアウトしました"
        }
    }
}

class SpeechRecognitionManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var recognitionTimer: Timer?
    private var segmentTimer: Timer?
    private var currentSegmentText = ""
    private var accumulatedText = ""
    
    @Published var transcribedText: String = ""
    @Published var isRecognizing: Bool = false
    @Published var currentLanguage: SpeechLanguage = .japanese
    @Published var recognitionQuality: Float = 0.0
    @Published var lastError: SpeechRecognitionError?
    @Published var isAvailable: Bool = false

    override init() {
        super.init()
        setupSpeechRecognizer()
        checkAvailability()
    }
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: currentLanguage.locale)
        speechRecognizer?.delegate = self
    }
    
    private func checkAvailability() {
        DispatchQueue.main.async {
            self.isAvailable = SFSpeechRecognizer.authorizationStatus() == .authorized &&
                               self.speechRecognizer?.isAvailable == true
        }
    }

    func changeLanguage(to language: SpeechLanguage) {
        guard !isRecognizing else { return }
        
        currentLanguage = language
        setupSpeechRecognizer()
        checkAvailability()
    }
    
    func requestPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                DispatchQueue.main.async {
                    self.isAvailable = authStatus == .authorized && self.speechRecognizer?.isAvailable == true
                }
                continuation.resume(returning: authStatus == .authorized)
            }
        }
    }
    
    func startSpeechRecognition() async throws {
        // 権限確認
        guard await requestPermissions() else {
            throw SpeechRecognitionError.unauthorized
        }
        
        guard speechRecognizer?.isAvailable == true else {
            throw SpeechRecognitionError.unavailable
        }
        
        // 既存の認識をクリーンアップ
        await stopSpeechRecognition()
        
        // 音声セッション設定
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognitionError.configurationFailed
        }
        
        await startRecognitionSegment()
    }
    
    private func startRecognitionSegment() async {
        guard !isRecognizing else { return }
        
        // 新しい認識セグメントを開始
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        // 音声認識タスクを作成
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.processRecognitionResult(result: result, error: error)
            }
        }
        
        // 音声入力設定
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, when in
            self?.recognitionRequest?.append(buffer)
        }
        
        // 音声エンジン開始
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            await MainActor.run {
                self.isRecognizing = true
                self.lastError = nil
                self.currentSegmentText = ""
            }
            
            // 50秒後に自動的にセグメントを更新（1分制限対策）
            segmentTimer = Timer.scheduledTimer(withTimeInterval: 50.0, repeats: false) { [weak self] _ in
                Task {
                    await self?.restartRecognitionSegment()
                }
            }
            
        } catch {
            await MainActor.run {
                self.lastError = .configurationFailed
            }
        }
    }
    
    private func processRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            self.lastError = .recognitionFailed(error.localizedDescription)
            return
        }
        
        guard let result = result else { return }
        
        // 現在のセグメントテキストを更新
        currentSegmentText = result.bestTranscription.formattedString
        
        // 全体のテキストを更新
        transcribedText = accumulatedText + currentSegmentText
        
        // 認識品質を更新
        if let segment = result.bestTranscription.segments.last {
            recognitionQuality = segment.confidence
        }
        
        // 最終結果の場合、セグメントを確定
        if result.isFinal {
            accumulatedText += currentSegmentText
            currentSegmentText = ""
        }
    }
    
    private func restartRecognitionSegment() async {
        guard isRecognizing else { return }
        
        // 現在のセグメントを確定
        await MainActor.run {
            accumulatedText += currentSegmentText
            currentSegmentText = ""
        }
        
        // 認識タスクを停止して新しいセグメントを開始
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // 少し待ってから新しいセグメントを開始
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        await startRecognitionSegment()
    }

    func stopSpeechRecognition() async {
        segmentTimer?.invalidate()
        segmentTimer = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        // 最終的なテキストを確定
        await MainActor.run {
            accumulatedText += currentSegmentText
            transcribedText = accumulatedText
            currentSegmentText = ""
            isRecognizing = false
        }
        
        // 音声セッションを非アクティブ化
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    func clearTranscription() {
        transcribedText = ""
        accumulatedText = ""
        currentSegmentText = ""
    }

    // 音声ファイルからの認識（録音済みファイル用）
    func recognizeAudioFile(url: URL) async throws -> String {
        let recognitionRequest = SFSpeechURLRecognitionRequest(url: url)
        recognitionRequest.shouldReportPartialResults = false
        
        return try await withCheckedThrowingContinuation { continuation in
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - SFSpeechRecognizerDelegate
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            self.isAvailable = available && SFSpeechRecognizer.authorizationStatus() == .authorized
            
            if !available && self.isRecognizing {
                Task {
                    await self.stopSpeechRecognition()
                    self.lastError = .unavailable
                }
            }
        }
    }
    
    // MARK: - Utility Functions
    
    func getTranscribedText() -> String {
        return transcribedText
    }
    
    func isCurrentlyRecognizing() -> Bool {
        return isRecognizing
    }
    
    func getCurrentLanguage() -> SpeechLanguage {
        return currentLanguage
    }
    
    func getSupportedLanguages() -> [SpeechLanguage] {
        return SpeechLanguage.allCases
    }
}
