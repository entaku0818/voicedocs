import Foundation
import AVFoundation

/// Unified transcription result that works across all implementations
struct TranscriptionResult: Equatable {
    let text: String
    let isFinal: Bool
    let confidence: Float
    let locale: Locale

    static func == (lhs: TranscriptionResult, rhs: TranscriptionResult) -> Bool {
        lhs.text == rhs.text &&
        lhs.isFinal == rhs.isFinal &&
        lhs.confidence == rhs.confidence &&
        lhs.locale.identifier == rhs.locale.identifier
    }
}

/// Configuration for transcription
struct TranscriptionConfiguration {
    let locale: Locale
    let enableVolatileResults: Bool

    static var `default`: TranscriptionConfiguration {
        TranscriptionConfiguration(
            locale: Locale(identifier: "ja-JP"),
            enableVolatileResults: true
        )
    }

    static var japanese: TranscriptionConfiguration {
        TranscriptionConfiguration(
            locale: Locale(identifier: "ja-JP"),
            enableVolatileResults: true
        )
    }

    static var japaneseWithoutVolatile: TranscriptionConfiguration {
        TranscriptionConfiguration(
            locale: Locale(identifier: "ja-JP"),
            enableVolatileResults: false
        )
    }
}

/// Unified protocol for transcription services (iOS 26+)
protocol TranscriptionServiceProtocol: AnyObject {
    /// Service availability
    var isAvailable: Bool { get async }

    /// Current transcription state
    var isTranscribing: Bool { get }

    /// Check if a locale is supported
    func isLocaleSupported(_ locale: Locale) async -> Bool

    /// Check if the model for a locale is installed
    func isModelInstalled(for locale: Locale) async -> Bool

    /// Download model for a locale if needed
    func downloadModelIfNeeded(for locale: Locale) async throws

    /// Transcribe an audio file (batch processing) - returns final result only
    func transcribeFile(at url: URL, configuration: TranscriptionConfiguration) async throws -> String

    /// Transcribe an audio file with real-time progress updates
    func transcribeFileWithProgress(
        at url: URL,
        configuration: TranscriptionConfiguration,
        onProgress: @escaping (TranscriptionResult) -> Void
    ) async throws -> String

    /// Cancel transcription
    func cancelTranscription() async
}
