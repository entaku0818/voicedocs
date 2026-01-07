import Foundation
import AVFoundation
import Speech

/// SpeechAnalyzer-based transcription service for iOS 26+
/// Uses Apple's new high-accuracy on-device transcription
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
        let localeId = locale.identifier(.bcp47)
        return supported.map { $0.identifier(.bcp47) }.contains(localeId)
    }

    func isModelInstalled(for locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        let localeId = locale.identifier(.bcp47)
        return installed.map { $0.identifier(.bcp47) }.contains(localeId)
    }

    // MARK: - Model Download

    func downloadModelIfNeeded(for locale: Locale) async throws {
        guard await isLocaleSupported(locale) else {
            throw TranscriptionError.localeNotSupported
        }

        if await isModelInstalled(for: locale) {
            return
        }

        // Create a temporary transcriber for download
        let tempTranscriber = SpeechTranscriber(
            locale: locale,
            preset: .offlineTranscription
        )

        if let downloader = try await AssetInventory.assetInstallationRequest(
            supporting: [tempTranscriber]
        ) {
            try await downloader.downloadAndInstall()
        }
    }

    // MARK: - File Transcription

    func transcribeFile(
        at url: URL,
        configuration: TranscriptionConfiguration
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

        // Create transcriber with offline preset for best accuracy
        let transcriber = SpeechTranscriber(
            locale: configuration.locale,
            preset: .offlineTranscription
        )

        // Setup result accumulation using async let
        async let transcriptionFuture: String = {
            var result = ""
            for try await segment in transcriber.results {
                result += segment.text
            }
            return result
        }()

        // Process file with SpeechAnalyzer
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        self.transcriber = transcriber

        if let lastSample = try await analyzer.analyzeSequence(from: url) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
            throw TranscriptionError.noAudioData
        }

        let transcribedText = try await transcriptionFuture

        // Handle empty or "no speech" results
        if transcribedText.isEmpty {
            return ""
        }

        return transcribedText
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
