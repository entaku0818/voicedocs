//
//  SpeechRecognitionManager.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/01.
//

import Foundation
import Speech
import AVFoundation
import os.log
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
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var transcribedText: String = ""
    @Published var isTranscribing: Bool = false
    @Published var currentLanguage: SpeechLanguage = .japanese
    @Published var recognitionQuality: Float = 0.0
    @Published var lastError: SpeechRecognitionError?
    @Published var isAvailable: Bool = false
    @Published var transcriptionProgress: String = ""

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
    
    // ファイルベースの文字起こし（新しいメイン機能）
    func transcribeAudioFile(at url: URL) async throws -> String {
        AppLogger.speechRecognition.debug("transcribeAudioFile called with URL: \(url.path)")
        
        // 権限確認
        guard await requestPermissions() else {
            AppLogger.speechRecognition.error("No permission")
            throw SpeechRecognitionError.unauthorized
        }
        AppLogger.speechRecognition.debug("Permission granted")
        
        guard speechRecognizer?.isAvailable == true else {
            AppLogger.speechRecognition.error("Recognizer not available")
            throw SpeechRecognitionError.unavailable
        }
        AppLogger.speechRecognition.debug("Recognizer available")
        
        // ファイルの存在確認
        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLogger.speechRecognition.error("File not found at: \(url.path)")
            throw SpeechRecognitionError.recognitionFailed("Audio file not found")
        }
        AppLogger.speechRecognition.debug("File exists")
        
        // ファイルサイズ確認
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            AppLogger.speechRecognition.info("File size: \(fileSize) bytes")
            
            if fileSize == 0 {
                AppLogger.speechRecognition.error("File is empty")
                throw SpeechRecognitionError.recognitionFailed("Audio file is empty")
            }
        } catch {
            AppLogger.speechRecognition.error("Failed to access file: \(error.localizedDescription)")
            throw SpeechRecognitionError.recognitionFailed("Failed to access audio file")
        }
        
        await MainActor.run {
            self.isTranscribing = true
            self.transcriptionProgress = "音声ファイルを解析中..."
            self.lastError = nil
        }
        
        AppLogger.speechRecognition.info("Starting performFileTranscription...")
        return try await performFileTranscription(url: url)
    }
    
    private func performFileTranscription(url: URL) async throws -> String {
        AppLogger.speechRecognition.debug("performFileTranscription called")
        
        return try await withCheckedThrowingContinuation { continuation in
            let recognitionRequest = SFSpeechURLRecognitionRequest(url: url)
            recognitionRequest.shouldReportPartialResults = false
            recognitionRequest.requiresOnDeviceRecognition = false
            
            AppLogger.speechRecognition.debug("Creating recognition task...")
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        AppLogger.speechRecognition.error("Recognition error: \(error.localizedDescription)")
                        self?.isTranscribing = false
                        self?.transcriptionProgress = ""
                        continuation.resume(throwing: SpeechRecognitionError.recognitionFailed(error.localizedDescription))
                        return
                    }
                    
                    if let result = result {
                        let transcription = result.bestTranscription.formattedString
                        AppLogger.speechRecognition.debug("Transcription progress: \(transcription.count) characters, isFinal: \(result.isFinal)")
                        
                        // 認識品質を更新
                        if let segment = result.bestTranscription.segments.last {
                            self?.recognitionQuality = segment.confidence
                            AppLogger.speechRecognition.debug("Recognition quality: \(segment.confidence)")
                        }
                        
                        // 進行状況を更新
                        self?.transcriptionProgress = "文字起こし中: \(transcription.count)文字"
                        
                        if result.isFinal {
                            AppLogger.speechRecognition.info("Transcription completed: \(transcription.prefix(100))...")
                            self?.transcribedText = transcription
                            self?.isTranscribing = false
                            self?.transcriptionProgress = "文字起こし完了"
                            continuation.resume(returning: transcription)
                        }
                    }
                }
            }
            
            if recognitionTask == nil {
                AppLogger.speechRecognition.error("Failed to create recognition task")
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.transcriptionProgress = ""
                }
                continuation.resume(throwing: SpeechRecognitionError.configurationFailed)
            } else {
                AppLogger.speechRecognition.debug("Recognition task created successfully")
            }
        }
    }
    
    // 文字起こし状態をリセット
    func resetTranscription() {
        transcribedText = ""
        recognitionQuality = 0.0
        transcriptionProgress = ""
        lastError = nil
    }
    
    // 文字起こしをキャンセル
    func cancelTranscription() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async {
            self.isTranscribing = false
            self.transcriptionProgress = "文字起こしがキャンセルされました"
        }
    }

    // 後方互換性のため残しておく（使用しない）
    func stopSpeechRecognition() async {
        cancelTranscription()
    }
    
    func clearTranscription() {
        transcribedText = ""
        recognitionQuality = 0.0
        transcriptionProgress = ""
        lastError = nil
    }

    // 後方互換性のため残しておく（transcribeAudioFileを使用することを推奨）
    func recognizeAudioFile(url: URL) async throws -> String {
        return try await transcribeAudioFile(at: url)
    }

    // MARK: - SFSpeechRecognizerDelegate
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            self.isAvailable = available && SFSpeechRecognizer.authorizationStatus() == .authorized
            
            if !available && self.isTranscribing {
                self.cancelTranscription()
                self.lastError = .unavailable
            }
        }
    }
    
    // MARK: - Utility Functions
    
    func getTranscribedText() -> String {
        return transcribedText
    }
    
    func isCurrentlyRecognizing() -> Bool {
        return isTranscribing
    }
    
    func getCurrentLanguage() -> SpeechLanguage {
        return currentLanguage
    }
    
    func getSupportedLanguages() -> [SpeechLanguage] {
        return SpeechLanguage.allCases
    }
}
