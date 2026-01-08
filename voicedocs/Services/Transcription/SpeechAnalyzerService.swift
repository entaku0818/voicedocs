import Foundation
import AVFoundation
import Speech
import os

private let logger = Logger(subsystem: "com.entaku.voicedocs", category: "SpeechAnalyzer")

/// SpeechAnalyzer-based transcription service for iOS 26+
/// Uses Apple's new high-accuracy on-device transcription with real-time support
@available(iOS 26.0, *)
final class SpeechAnalyzerService: TranscriptionServiceProtocol {

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?

    private(set) var isTranscribing: Bool = false

    // MARK: - Availability

    var isAvailable: Bool {
        get async {
            let locale = Locale(identifier: "ja-JP")
            return await isLocaleSupported(locale)
        }
    }

    // MARK: - Locale Support

    func isLocaleSupported(_ locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier == locale.identifier }
    }

    func isModelInstalled(for locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier == locale.identifier }
    }

    // MARK: - Model Download

    func downloadModelIfNeeded(for locale: Locale) async throws {
        guard await isLocaleSupported(locale) else {
            throw TranscriptionError.localeNotSupported
        }

        if await isModelInstalled(for: locale) {
            return
        }

        let tempTranscriber = SpeechTranscriber(locale: locale, preset: .transcription)

        if let downloader = try await AssetInventory.assetInstallationRequest(
            supporting: [tempTranscriber]
        ) {
            try await downloader.downloadAndInstall()
        }
    }

    // MARK: - File Transcription (Batch)

    func transcribeFile(
        at url: URL,
        configuration: TranscriptionConfiguration
    ) async throws -> String {
        try await transcribeFileWithProgress(at: url, configuration: configuration) { _ in }
    }

    // MARK: - File Transcription with Real-time Progress

    func transcribeFileWithProgress(
        at url: URL,
        configuration: TranscriptionConfiguration,
        onProgress: @escaping (TranscriptionResult) -> Void
    ) async throws -> String {
        logger.info("transcribeFileWithProgress started")
        logger.info("URL: \(url.path)")
        logger.info("enableVolatileResults: \(configuration.enableVolatileResults)")

        guard !isTranscribing else {
            logger.error("Already transcribing")
            throw TranscriptionError.alreadyTranscribing
        }

        isTranscribing = true
        defer {
            isTranscribing = false
            cleanup()
        }

        // Ensure model is downloaded
        logger.info("Checking model...")
        try await downloadModelIfNeeded(for: configuration.locale)
        logger.info("Model ready")

        // Create transcriber with or without volatile results
        let transcriber: SpeechTranscriber
        if configuration.enableVolatileResults {
            logger.info("Creating transcriber with volatileResults")
            transcriber = SpeechTranscriber(
                locale: configuration.locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
        } else {
            logger.info("Creating transcriber with preset")
            transcriber = SpeechTranscriber(locale: configuration.locale, preset: .transcription)
        }
        self.transcriber = transcriber

        // Setup result accumulation with progress callback
        let resultTask = Task<String, Error> {
            logger.info("Result task started, waiting for segments...")
            var finalizedText = ""
            var segmentCount = 0
            for try await segment in transcriber.results {
                segmentCount += 1
                let text = String(segment.text.characters)
                logger.info("Segment #\(segmentCount): isFinal=\(segment.isFinal), text='\(text)'")

                let result = TranscriptionResult(
                    text: text,
                    isFinal: segment.isFinal,
                    confidence: 1.0,
                    locale: configuration.locale
                )

                // Call progress callback on main thread
                await MainActor.run {
                    logger.debug("Calling onProgress callback")
                    onProgress(result)
                }

                if segment.isFinal {
                    finalizedText += text
                }
            }
            logger.info("Result task finished, total segments: \(segmentCount)")
            return finalizedText
        }

        // Process file with SpeechAnalyzer
        logger.info("Creating analyzer...")
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        logger.info("Opening audio file...")
        let audioFile = try AVAudioFile(forReading: url)
        logger.info("Audio file opened, length: \(audioFile.length) frames")

        logger.info("Starting analyzeSequence...")
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            logger.info("analyzeSequence completed, lastSample: \(lastSample.seconds) seconds")
            logger.info("Calling finalizeAndFinish...")
            try await analyzer.finalizeAndFinish(through: lastSample)
            logger.info("finalizeAndFinish completed")
        } else {
            logger.error("No audio data")
            await analyzer.cancelAndFinishNow()
            throw TranscriptionError.noAudioData
        }

        logger.info("Waiting for result task...")
        let result = try await resultTask.value
        logger.info("Final result: '\(result)'")
        return result
    }

    // MARK: - Cancellation

    func cancelTranscription() async {
        await analyzer?.cancelAndFinishNow()
        cleanup()
    }

    // MARK: - Private

    private func cleanup() {
        analyzer = nil
        transcriber = nil
    }
}
