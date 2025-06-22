//
//  BackgroundTranscriptionManager.swift
//  voicedocs
//
//  Created by Claude on 2025/6/20.
//

import Foundation
import Speech
import AVFoundation
import os.log
import BackgroundTasks
import Combine
import UIKit

enum TranscriptionState: Equatable {
    case idle
    case processing
    case paused
    case completed
    case failed(String)
}

struct TranscriptionProgress: Equatable {
    let currentSegment: Int
    let totalSegments: Int
    let processedDuration: TimeInterval
    let totalDuration: TimeInterval
    let transcribedText: String
    
    var percentage: Double {
        guard totalSegments > 0 else { return 0.0 }
        return Double(currentSegment) / Double(totalSegments)
    }
}

class BackgroundTranscriptionManager: NSObject, ObservableObject {
    static let shared = BackgroundTranscriptionManager()
    
    @Published var state: TranscriptionState = .idle
    @Published var progress: TranscriptionProgress = TranscriptionProgress(
        currentSegment: 0, 
        totalSegments: 0, 
        processedDuration: 0, 
        totalDuration: 0, 
        transcribedText: ""
    )
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var currentTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private let segmentDuration: TimeInterval = 60.0 // 60秒セグメント
    private var pausedAt: TimeInterval = 0
    private var audioFile: AVAudioFile?
    private var totalDuration: TimeInterval = 0
    
    private var accumulatedText: String = ""
    private var currentMemoId: UUID?
    
    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        registerBackgroundTask()
    }
    
    // MARK: - Background Task Registration
    
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.voicedocs.transcription", using: nil) { task in
            self.handleBackgroundTranscription(task: task as! BGProcessingTask)
        }
    }
    
    private func handleBackgroundTranscription(task: BGProcessingTask) {
        task.expirationHandler = {
            // タスクが期限切れになる前に現在の進捗を保存
            self.pauseTranscription()
            task.setTaskCompleted(success: false)
        }
        
        // バックグラウンドでの文字起こしを継続
        Task {
            await self.continueBackgroundTranscription()
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Public Methods
    
    func startTranscription(audioURL: URL, memoId: UUID) async {
        await MainActor.run {
            self.currentMemoId = memoId
            self.state = .processing
            self.accumulatedText = ""
            self.pausedAt = 0
        }
        
        do {
            audioFile = try AVAudioFile(forReading: audioURL)
            totalDuration = Double(audioFile!.length) / audioFile!.fileFormat.sampleRate
            
            await MainActor.run {
                self.progress = TranscriptionProgress(
                    currentSegment: 0,
                    totalSegments: Int(ceil(totalDuration / segmentDuration)),
                    processedDuration: 0,
                    totalDuration: totalDuration,
                    transcribedText: ""
                )
            }
            
            currentTask = Task {
                await processAudioFileInSegments(audioURL: audioURL)
            }
            
            // バックグラウンドタスクを開始
            startBackgroundTask()
            
        } catch {
            await MainActor.run {
                self.state = .failed("音声ファイルの読み込みに失敗しました: \(error.localizedDescription)")
            }
        }
    }
    
    func pauseTranscription() {
        guard state == .processing else { return }
        
        currentTask?.cancel()
        currentTask = nil
        
        DispatchQueue.main.async {
            self.state = .paused
            self.pausedAt = self.progress.processedDuration
        }
        
        endBackgroundTask()
    }
    
    func resumeTranscription() async {
        guard state == .paused, let audioFile = audioFile else { return }
        
        await MainActor.run {
            self.state = .processing
        }
        
        currentTask = Task {
            await resumeFromPausedPosition()
        }
        
        startBackgroundTask()
    }
    
    func stopTranscription() {
        currentTask?.cancel()
        currentTask = nil
        
        DispatchQueue.main.async {
            self.state = .idle
            self.progress = TranscriptionProgress(
                currentSegment: 0,
                totalSegments: 0,
                processedDuration: 0,
                totalDuration: 0,
                transcribedText: ""
            )
            self.accumulatedText = ""
            self.pausedAt = 0
        }
        
        endBackgroundTask()
    }
    
    // MARK: - Private Methods
    
    private func processAudioFileInSegments(audioURL: URL) async {
        guard let audioFile = audioFile else { return }
        
        let format = audioFile.processingFormat
        let totalFrames = audioFile.length
        let segmentFrames = AVAudioFrameCount(segmentDuration * format.sampleRate)
        
        var currentFrame: AVAudioFramePosition = AVAudioFramePosition(pausedAt * format.sampleRate)
        var segmentIndex = Int(pausedAt / segmentDuration)
        
        while currentFrame < totalFrames && !Task.isCancelled {
            let remainingFrames = totalFrames - currentFrame
            let framesToRead = min(segmentFrames, AVAudioFrameCount(remainingFrames))
            
            do {
                // セグメントを抽出
                let segmentURL = try await extractAudioSegment(
                    from: audioURL,
                    startFrame: currentFrame,
                    frameCount: framesToRead,
                    format: format
                )
                
                // セグメントを文字起こし
                let segmentText = try await transcribeSegment(segmentURL)
                
                // 進捗を更新
                await MainActor.run {
                    self.accumulatedText += segmentText
                    let processedDuration = Double(currentFrame + AVAudioFramePosition(framesToRead)) / format.sampleRate
                    
                    self.progress = TranscriptionProgress(
                        currentSegment: segmentIndex + 1,
                        totalSegments: self.progress.totalSegments,
                        processedDuration: processedDuration,
                        totalDuration: self.totalDuration,
                        transcribedText: self.accumulatedText
                    )
                }
                
                // メモを更新
                if let memoId = currentMemoId {
                    updateMemoTranscription(memoId: memoId, text: accumulatedText)
                }
                
                // 一時ファイルを削除
                try? FileManager.default.removeItem(at: segmentURL)
                
                currentFrame += AVAudioFramePosition(framesToRead)
                segmentIndex += 1
                
                // 少し待機してCPU負荷を軽減
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                
            } catch {
                await MainActor.run {
                    self.state = .failed("セグメント処理エラー: \(error.localizedDescription)")
                }
                return
            }
        }
        
        if !Task.isCancelled {
            await MainActor.run {
                self.state = .completed
            }
        }
        
        endBackgroundTask()
    }
    
    private func resumeFromPausedPosition() async {
        guard let audioFile = audioFile else { return }
        
        let audioURL = audioFile.url
        await processAudioFileInSegments(audioURL: audioURL)
    }
    
    private func extractAudioSegment(
        from sourceURL: URL,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        format: AVAudioFormat
    ) async throws -> URL {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        
        // 一時ファイルのURL
        let tempDir = FileManager.default.temporaryDirectory
        let segmentURL = tempDir.appendingPathComponent("segment_\(UUID().uuidString).wav")
        
        let outputFile = try AVAudioFile(
            forWriting: segmentURL,
            settings: format.settings
        )
        
        // バッファを作成してセグメントを読み込み
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        sourceFile.framePosition = startFrame
        try sourceFile.read(into: buffer, frameCount: frameCount)
        
        // セグメントファイルに書き込み
        try outputFile.write(from: buffer)
        
        return segmentURL
    }
    
    private func transcribeSegment(_ segmentURL: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: segmentURL)
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = false
            
            speechRecognizer?.recognitionTask(with: request) { result, error in
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
    
    private func updateMemoTranscription(memoId: UUID, text: String) {
        let controller = VoiceMemoController.shared
        _ = controller.updateVoiceMemo(id: memoId, title: nil, text: text)
    }
    
    private func continueBackgroundTranscription() async {
        guard state == .processing else { return }
        // バックグラウンドでの処理継続ロジック
        // 現在の処理を継続
    }
    
    // MARK: - Background Task Management
    
    private func startBackgroundTask() {
        endBackgroundTask() // 既存のタスクがあれば終了
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Transcription") {
            // タスクの期限が来た場合
            self.pauseTranscription()
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    // MARK: - Schedule Background Processing
    
    func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: "com.voicedocs.transcription")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.speechRecognition.error("Could not schedule background transcription: \(error.localizedDescription)")
        }
    }
}