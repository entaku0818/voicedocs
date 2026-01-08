//
//  RealtimeTranscriptionRecorder.swift
//  voicedocs
//
//  Recording with real-time transcription using AVAudioEngine and SFSpeechRecognizer
//

import Foundation
import AVFoundation
import Speech
import os
import UIKit

private let logger = Logger(subsystem: "com.entaku.voicedocs", category: "RealtimeRecorder")

/// Recorder that provides real-time transcription during recording
@available(iOS 26.0, *)
final class RealtimeTranscriptionRecorder: NSObject, ObservableObject {

    // MARK: - Audio Engine Components

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingSession: AVAudioSession!
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Speech Recognition Components

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Published Properties

    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText: String = ""
    @Published var isTranscribing: Bool = false
    @Published var lastError: Error?

    // MARK: - Recording Properties

    var audioFileURL: URL?
    private var startTime: Date?
    private var recordingTimer: Timer?
    private let locale: Locale

    // MARK: - Initialization

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.locale = locale
        super.init()
        setupRecordingSession()
        setupSpeechRecognizer()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupRecordingSession() {
        recordingSession = AVAudioSession.sharedInstance()

        do {
            try recordingSession.setCategory(.playAndRecord,
                                             mode: .default,
                                             options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        } catch {
            logger.error("Failed to setup recording session: \(error.localizedDescription)")
        }
    }

    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        logger.info("Speech recognizer created for locale: \(self.locale.identifier)")
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        logger.info("startRecording called")

        guard !isRecording else {
            logger.warning("Already recording")
            return
        }

        // Request permissions
        let granted = await requestPermissions()
        guard granted else {
            logger.error("Permissions not granted")
            throw TranscriptionError.permissionDenied
        }

        logger.info("Permissions granted, starting recording...")

        do {
            // Activate audio session
            try recordingSession.setActive(true, options: [])
            logger.info("Audio session activated")

            // Setup audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                throw TranscriptionError.configurationFailed
            }

            // Create output file URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let voiceRecordingsPath = documentsPath.appendingPathComponent("VoiceRecordings")

            if !FileManager.default.fileExists(atPath: voiceRecordingsPath.path) {
                try FileManager.default.createDirectory(at: voiceRecordingsPath,
                                                       withIntermediateDirectories: true,
                                                       attributes: nil)
            }

            let audioFilename = voiceRecordingsPath.appendingPathComponent("\(UUID().uuidString).m4a")
            audioFileURL = audioFilename
            logger.info("Audio file URL: \(audioFilename.path)")

            // Get input node
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            logger.info("Recording format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")

            // Create audio file for recording
            let m4aSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: recordingFormat.sampleRate,
                AVNumberOfChannelsKey: recordingFormat.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioFile = try AVAudioFile(forWriting: audioFilename, settings: m4aSettings)
            logger.info("Audio file created")

            // Setup speech recognition
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                throw TranscriptionError.configurationFailed
            }

            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = false
            logger.info("Recognition request created with partialResults=true")

            // Start recognition task
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    // Ignore cancellation errors when stopping
                    if (error as NSError).code != 216 { // Speech recognition canceled
                        logger.error("Recognition error: \(error.localizedDescription)")
                    }
                    return
                }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal

                    logger.info("Transcription update: isFinal=\(isFinal), text='\(text.prefix(50))...'")

                    DispatchQueue.main.async {
                        self.transcribedText = text
                    }
                }
            }

            logger.info("Recognition task started")

            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
                guard let self = self else { return }

                // Write to file
                do {
                    try self.audioFile?.write(from: buffer)
                } catch {
                    logger.error("Failed to write audio buffer: \(error.localizedDescription)")
                }

                // Update audio level
                self.updateAudioLevel(buffer: buffer)

                // Feed to speech recognizer
                self.recognitionRequest?.append(buffer)
            }

            // Start audio engine
            try audioEngine.start()
            logger.info("Audio engine started")

            await MainActor.run {
                self.isRecording = true
                self.isTranscribing = true
                self.startTime = Date()
                self.recordingDuration = 0
                self.transcribedText = ""
                self.lastError = nil
            }

            startRecordingTimer()
            startBackgroundTask()

            logger.info("Recording started successfully")

        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            await cleanup()
            throw error
        }
    }

    func stopRecording() async {
        logger.info("stopRecording called")

        guard isRecording else {
            logger.warning("Not recording")
            return
        }

        // Stop audio engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        logger.info("Audio engine stopped")

        // Stop speech recognition
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        logger.info("Speech recognition stopped")

        // Cleanup
        recordingTimer?.invalidate()
        recordingTimer = nil

        await MainActor.run {
            self.isRecording = false
            self.isTranscribing = false
        }

        endBackgroundTask()

        // Deactivate audio session
        do {
            try recordingSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }

        await cleanup()
        logger.info("Recording stopped")
    }

    // MARK: - Audio Processing

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0

        for i in 0..<frameCount {
            sum += abs(channelData[i])
        }

        let average = sum / Float(frameCount)
        let normalizedLevel = min(1.0, average * 10)

        DispatchQueue.main.async {
            self.audioLevel = normalizedLevel
        }
    }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        // Request microphone permission
        let micPermission = await AVAudioApplication.requestRecordPermission()

        guard micPermission else {
            logger.error("Microphone permission denied")
            return false
        }

        // Request speech recognition permission
        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechPermission else {
            logger.error("Speech recognition permission denied")
            return false
        }

        return true
    }

    // MARK: - Timer

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateRecordingProgress()
        }
    }

    private func updateRecordingProgress() {
        guard let startTime = startTime else { return }

        let newDuration = Date().timeIntervalSince(startTime)

        DispatchQueue.main.async {
            self.recordingDuration = newDuration
        }
    }

    // MARK: - Background Task

    @objc private func handleAppWillResignActive() {
        if isRecording {
            startBackgroundTask()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        endBackgroundTask()
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
                logger.info("Audio session interrupted")
            }
        case .ended:
            logger.info("Audio session interruption ended")
        @unknown default:
            break
        }
    }

    private func startBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "RealtimeRecording") {
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - Cleanup

    private func cleanup() async {
        audioEngine = nil
        audioFile = nil
        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - Public Methods

    func resetTranscription() {
        transcribedText = ""
        lastError = nil
    }
}
