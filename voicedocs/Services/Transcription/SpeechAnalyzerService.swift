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

        // Create a temporary transcriber for download
        let tempTranscriber = SpeechTranscriber(locale: locale, preset: .transcription)

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

        // Create transcriber with transcription preset for best accuracy
        let transcriber = SpeechTranscriber(locale: configuration.locale, preset: .transcription)
        self.transcriber = transcriber

        // Setup result accumulation
        let resultTask = Task<String, Error> {
            var result = ""
            for try await segment in transcriber.results {
                // Convert AttributedString to String
                result += String(segment.text.characters)
            }
            return result
        }

        // Process file with SpeechAnalyzer
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Open audio file
        let audioFile = try AVAudioFile(forReading: url)

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
            throw TranscriptionError.noAudioData
        }

        let transcribedText = try await resultTask.value

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
