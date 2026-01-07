import Foundation
import AVFoundation
import WhisperKit

/// Legacy transcription service using SFSpeechRecognizer and WhisperKit
/// Used for iOS 25 and earlier
final class LegacyTranscriptionService: TranscriptionServiceProtocol {

    private var whisperKit: WhisperKit?

    private(set) var isTranscribing: Bool = false

    var isAvailable: Bool {
        get async {
            // WhisperKit is always available as it runs on-device
            return true
        }
    }

    func isLocaleSupported(_ locale: Locale) async -> Bool {
        // WhisperKit supports Japanese and English
        let supportedIdentifiers = ["ja-JP", "ja", "en-US", "en"]
        return supportedIdentifiers.contains(locale.identifier) ||
               supportedIdentifiers.contains(locale.language.languageCode?.identifier ?? "")
    }

    func isModelInstalled(for locale: Locale) async -> Bool {
        // WhisperKit downloads models on demand, so we return true
        // The actual download happens during transcription
        return true
    }

    func downloadModelIfNeeded(for locale: Locale) async throws {
        // WhisperKit handles model download internally during initialization
        // Pre-initialize to trigger download if needed
        if whisperKit == nil {
            whisperKit = try await WhisperKit()
        }
    }

    // MARK: - File Transcription (uses WhisperKit for high accuracy)

    func transcribeFile(
        at url: URL,
        configuration: TranscriptionConfiguration
    ) async throws -> String {
        guard !isTranscribing else {
            throw TranscriptionError.alreadyTranscribing
        }

        isTranscribing = true
        defer { isTranscribing = false }

        // Initialize WhisperKit if needed
        if whisperKit == nil {
            whisperKit = try await WhisperKit()
        }

        guard let whisper = whisperKit else {
            throw TranscriptionError.initializationFailed
        }

        // Extract language code from locale
        let languageCode = configuration.locale.language.languageCode?.identifier ?? "ja"

        let results = try await whisper.transcribe(
            audioPath: url.path,
            decodeOptions: DecodingOptions(language: languageCode)
        )

        let transcribedText = results.map { $0.text }.joined(separator: "\n")

        // Handle "No speech detected" as empty result instead of error
        if transcribedText.isEmpty || transcribedText.lowercased().contains("no speech") {
            return ""
        }

        return transcribedText
    }

    func cancelTranscription() async {
        // WhisperKit doesn't support cancellation during transcription
        // The flag will be reset after current transcription completes
        isTranscribing = false
    }
}
