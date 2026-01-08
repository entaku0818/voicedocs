import Foundation

/// Factory for creating transcription services (iOS 26+)
@available(iOS 26.0, *)
final class TranscriptionServiceFactory {

    static let shared = TranscriptionServiceFactory()

    private var cachedService: TranscriptionServiceProtocol?

    private init() {}

    /// Create or return cached transcription service
    func createService() -> TranscriptionServiceProtocol {
        if let cached = cachedService {
            return cached
        }

        let service = SpeechAnalyzerService()
        cachedService = service
        return service
    }

    /// Clear cached service (useful for testing)
    func clearCache() {
        cachedService = nil
    }
}
