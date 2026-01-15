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
import BackgroundTasks

// MARK: - Transcription Progress
struct TranscriptionProgress {
    var currentChunk: Int = 0
    var totalChunks: Int = 0
    var processedDuration: TimeInterval = 0
    var totalDuration: TimeInterval = 0
    var transcribedText: String = ""
    var status: TranscriptionStatus = .idle

    var progressPercentage: Double {
        guard totalDuration > 0 else { return 0 }
        return min(processedDuration / totalDuration * 100, 100)
    }

    var progressDescription: String {
        switch status {
        case .idle:
            return "待機中"
        case .preparing:
            return "準備中..."
        case .transcribing:
            return "文字起こし中: \(Int(progressPercentage))%"
        case .paused:
            return "一時停止中 (\(Int(progressPercentage))%)"
        case .completed:
            return "完了"
        case .failed(let error):
            return "エラー: \(error)"
        case .cancelled:
            return "キャンセル"
        }
    }

    enum TranscriptionStatus: Equatable {
        case idle
        case preparing
        case transcribing
        case paused
        case completed
        case failed(String)
        case cancelled
    }
}

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

    // MARK: - Published Properties
    @Published var transcribedText: String = ""
    @Published var isTranscribing: Bool = false
    @Published var currentLanguage: SpeechLanguage = .japanese
    @Published var recognitionQuality: Float = 0.0
    @Published var lastError: SpeechRecognitionError?
    @Published var isAvailable: Bool = false
    @Published var transcriptionProgress: String = ""

    // MARK: - Long File Processing Properties
    /// 長時間ファイル用の進捗状況
    @Published var progress: TranscriptionProgress = TranscriptionProgress()
    /// 一時停止フラグ
    private var isPaused: Bool = false
    /// キャンセルフラグ
    private var isCancelled: Bool = false
    /// チャンク分割時間（秒）- Speech Frameworkの制限は約1分
    private let chunkDuration: TimeInterval = 55.0
    /// 一時保存用のチャンク結果
    private var chunkResults: [String] = []
    /// 現在処理中のチャンクインデックス
    private var currentChunkIndex: Int = 0

    override init() {
        super.init()
        setupSpeechRecognizer()
        checkAvailability()
        
        // 権限が未決定の場合は自動的にリクエスト
        Task {
            await requestPermissionsIfNeeded()
        }
    }
    
    private func requestPermissionsIfNeeded() async {
        let currentStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
        if currentStatus == .notDetermined {
            AppLogger.speechRecognition.info("Speech recognition permission not determined, requesting...")
            _ = await requestPermissions()
        }
    }
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: currentLanguage.locale)
        speechRecognizer?.delegate = self
    }
    
    private func checkAvailability() {
        let authStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
        let recognizerAvailable = speechRecognizer?.isAvailable == true
        
        AppLogger.speechRecognition.info("Speech recognition status check - Auth: \(authStatus.rawValue), Recognizer available: \(recognizerAvailable)")
        
        DispatchQueue.main.async {
            self.isAvailable = authStatus == .authorized && recognizerAvailable
            
            if !self.isAvailable {
                if authStatus != .authorized {
                    AppLogger.speechRecognition.warning("Speech recognition not authorized: \(authStatus.rawValue)")
                    self.lastError = .unauthorized
                }
                if !recognizerAvailable {
                    AppLogger.speechRecognition.warning("Speech recognizer not available for language: \(self.currentLanguage.rawValue)")
                    self.lastError = .unavailable
                }
            }
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
                        
                        // "No Speech detected"エラーの場合は成功として扱い、メッセージを返す
                        if error.localizedDescription.contains("No speech detected") || 
                           error.localizedDescription.contains("no speech detected") {
                            continuation.resume(returning: "文字起こし結果がありませんでした")
                        } else {
                            continuation.resume(throwing: SpeechRecognitionError.recognitionFailed(error.localizedDescription))
                        }
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
                            
                            // 空の結果または音声が検出されなかった場合の処理
                            if transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                continuation.resume(returning: "文字起こし結果がありませんでした")
                            } else {
                                continuation.resume(returning: transcription)
                            }
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
        progress = TranscriptionProgress()
        chunkResults = []
        currentChunkIndex = 0
        isPaused = false
        isCancelled = false
    }

    // 文字起こしをキャンセル
    func cancelTranscription() {
        isCancelled = true
        recognitionTask?.cancel()
        recognitionTask = nil

        DispatchQueue.main.async {
            self.isTranscribing = false
            self.transcriptionProgress = "文字起こしがキャンセルされました"
            self.progress.status = .cancelled
        }
    }

    // MARK: - 長時間ファイル対応

    /// 長時間音声ファイルを文字起こし（進捗付き）
    func transcribeLongAudioFile(at url: URL) async throws -> String {
        AppLogger.speechRecognition.info("Starting long file transcription: \(url.lastPathComponent)")

        // 初期化
        resetTranscription()

        // 権限確認
        guard await requestPermissions() else {
            throw SpeechRecognitionError.unauthorized
        }

        guard speechRecognizer?.isAvailable == true else {
            throw SpeechRecognitionError.unavailable
        }

        // ファイルの存在確認
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SpeechRecognitionError.recognitionFailed("音声ファイルが見つかりません")
        }

        await MainActor.run {
            self.isTranscribing = true
            self.progress.status = .preparing
        }

        // 音声の長さを取得
        let duration = try await getAudioDuration(url: url)
        AppLogger.speechRecognition.info("Audio duration: \(duration) seconds")

        await MainActor.run {
            self.progress.totalDuration = duration
        }

        // 短いファイルは通常処理
        if duration <= chunkDuration {
            AppLogger.speechRecognition.info("Short file, using standard transcription")
            let result = try await performFileTranscription(url: url)
            await MainActor.run {
                self.progress.status = .completed
                self.progress.processedDuration = duration
            }
            return result
        }

        // 長いファイルはチャンク分割して処理
        AppLogger.speechRecognition.info("Long file, using chunked transcription")
        return try await transcribeInChunks(url: url, totalDuration: duration)
    }

    /// 音声ファイルの長さを取得
    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    /// チャンク分割して文字起こし
    private func transcribeInChunks(url: URL, totalDuration: TimeInterval) async throws -> String {
        let totalChunks = Int(ceil(totalDuration / chunkDuration))

        await MainActor.run {
            self.progress.totalChunks = totalChunks
            self.progress.status = .transcribing
        }

        chunkResults = []
        currentChunkIndex = 0

        for chunkIndex in 0..<totalChunks {
            // キャンセルチェック
            if isCancelled {
                throw SpeechRecognitionError.recognitionFailed("キャンセルされました")
            }

            // 一時停止中は待機
            while isPaused {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
                if isCancelled {
                    throw SpeechRecognitionError.recognitionFailed("キャンセルされました")
                }
            }

            currentChunkIndex = chunkIndex
            let startTime = Double(chunkIndex) * chunkDuration
            let endTime = min(startTime + chunkDuration, totalDuration)

            await MainActor.run {
                self.progress.currentChunk = chunkIndex + 1
                self.transcriptionProgress = "チャンク \(chunkIndex + 1)/\(totalChunks) を処理中..."
            }

            AppLogger.speechRecognition.info("Processing chunk \(chunkIndex + 1)/\(totalChunks): \(startTime)s - \(endTime)s")

            // チャンクファイルを作成して文字起こし
            do {
                let chunkURL = try await createAudioChunk(from: url, startTime: startTime, duration: endTime - startTime)
                let chunkText = try await performFileTranscription(url: chunkURL)

                // 一時ファイルを削除
                try? FileManager.default.removeItem(at: chunkURL)

                if !chunkText.isEmpty && chunkText != "文字起こし結果がありませんでした" {
                    chunkResults.append(chunkText)
                }

                await MainActor.run {
                    self.progress.processedDuration = endTime
                    self.progress.transcribedText = self.chunkResults.joined(separator: " ")
                }
            } catch {
                AppLogger.speechRecognition.warning("Chunk \(chunkIndex + 1) failed: \(error.localizedDescription)")
                // 個別のチャンクエラーは無視して続行
            }
        }

        let finalText = chunkResults.joined(separator: " ")

        await MainActor.run {
            self.transcribedText = finalText
            self.isTranscribing = false
            self.progress.status = .completed
            self.progress.transcribedText = finalText
            self.transcriptionProgress = "文字起こし完了"
        }

        return finalText
    }

    /// 音声ファイルの一部を切り出して一時ファイルを作成
    private func createAudioChunk(from sourceURL: URL, startTime: TimeInterval, duration: TimeInterval) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        // 出力ファイルのURL
        let tempDir = FileManager.default.temporaryDirectory
        let chunkFileName = "chunk_\(UUID().uuidString).m4a"
        let chunkURL = tempDir.appendingPathComponent(chunkFileName)

        // エクスポートセッションを作成
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SpeechRecognitionError.recognitionFailed("音声エクスポートに失敗しました")
        }

        exportSession.outputURL = chunkURL
        exportSession.outputFileType = .m4a

        // 時間範囲を設定
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 1000)
        let durationCMTime = CMTime(seconds: duration, preferredTimescale: 1000)
        exportSession.timeRange = CMTimeRange(start: startCMTime, duration: durationCMTime)

        // エクスポート実行
        await exportSession.export()

        if exportSession.status == .completed {
            return chunkURL
        } else {
            let errorMessage = exportSession.error?.localizedDescription ?? "不明なエラー"
            throw SpeechRecognitionError.recognitionFailed("チャンク作成失敗: \(errorMessage)")
        }
    }

    // MARK: - 一時停止・再開

    /// 文字起こしを一時停止
    func pauseTranscription() {
        guard isTranscribing && !isPaused else { return }
        isPaused = true
        DispatchQueue.main.async {
            self.progress.status = .paused
            self.transcriptionProgress = "一時停止中..."
        }
        AppLogger.speechRecognition.info("Transcription paused at chunk \(currentChunkIndex + 1)")
    }

    /// 文字起こしを再開
    func resumeTranscription() {
        guard isPaused else { return }
        isPaused = false
        DispatchQueue.main.async {
            self.progress.status = .transcribing
            self.transcriptionProgress = "再開中..."
        }
        AppLogger.speechRecognition.info("Transcription resumed from chunk \(currentChunkIndex + 1)")
    }

    /// 一時停止中かどうか
    var isTranscriptionPaused: Bool {
        return isPaused
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
