import Foundation
import AVFoundation
import Speech

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
        guard !isTranscribing else {
            throw TranscriptionError.alreadyTranscribing
        }

        isTranscribing = true
        defer {
            isTranscribing = false
            cleanup()
        }

        // Ensure model is downloaded
        try await downloadModelIfNeeded(for: configuration.locale)

        // Create transcriber with or without volatile results
        let transcriber: SpeechTranscriber
        if configuration.enableVolatileResults {
            transcriber = SpeechTranscriber(
                locale: configuration.locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
        } else {
            transcriber = SpeechTranscriber(locale: configuration.locale, preset: .transcription)
        }
        self.transcriber = transcriber

        // Setup result accumulation with progress callback
        let resultTask = Task<String, Error> {
            var finalizedText = ""
            for try await segment in transcriber.results {
                let text = String(segment.text.characters)
                let result = TranscriptionResult(
                    text: text,
                    isFinal: segment.isFinal,
                    confidence: 1.0,
                    locale: configuration.locale
                )

                // Call progress callback on main thread
                await MainActor.run {
                    onProgress(result)
                }

                if segment.isFinal {
                    finalizedText += text
                }
            }
            return finalizedText
        }

        // Process file with SpeechAnalyzer
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let audioFile = try AVAudioFile(forReading: url)

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
            throw TranscriptionError.noAudioData
        }

        return try await resultTask.value
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
