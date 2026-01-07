import Foundation

/// Engine selection for transcription
enum TranscriptionEngine {
    case speechAnalyzer  // iOS 26+ native SpeechAnalyzer
    case legacy          // SFSpeechRecognizer + WhisperKit
    case auto            // Automatically select based on iOS version
}

/// Factory for creating transcription services based on iOS version
final class TranscriptionServiceFactory {

    static let shared = TranscriptionServiceFactory()

    private var cachedService: TranscriptionServiceProtocol?
    private var cachedEngine: TranscriptionEngine?

    private init() {}

    /// Create or return cached transcription service
    func createService(engine: TranscriptionEngine = .auto) -> TranscriptionServiceProtocol {
        // Return cached if engine matches
        if let cached = cachedService, cachedEngine == engine {
            return cached
        }

        let service: TranscriptionServiceProtocol

        switch engine {
        case .speechAnalyzer:
            if #available(iOS 26.0, *) {
                service = SpeechAnalyzerService()
            } else {
                // Fallback to legacy if iOS 26 not available
                service = LegacyTranscriptionService()
            }

        case .legacy:
            service = LegacyTranscriptionService()

        case .auto:
            if #available(iOS 26.0, *) {
                service = SpeechAnalyzerService()
            } else {
                service = LegacyTranscriptionService()
            }
        }

        cachedService = service
        cachedEngine = engine

        return service
    }

    /// Clear cached service (useful for testing)
    func clearCache() {
        cachedService = nil
        cachedEngine = nil
    }

    /// Check which engine is currently being used
    var currentEngine: TranscriptionEngine {
        if #available(iOS 26.0, *) {
            return .speechAnalyzer
        } else {
            return .legacy
        }
    }

    /// Check if SpeechAnalyzer is available on this device
    var isSpeechAnalyzerAvailable: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }
}
