import Foundation

/// Errors that can occur during transcription
enum TranscriptionError: LocalizedError, Equatable {
    case localeNotSupported
    case modelNotInstalled
    case modelDownloadFailed
    case initializationFailed
    case alreadyTranscribing
    case notStarted
    case noAudioData
    case audioConversionFailed
    case recognitionFailed(String)
    case timeout
    case permissionDenied
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .localeNotSupported:
            return "指定された言語はサポートされていません"
        case .modelNotInstalled:
            return "言語モデルがインストールされていません"
        case .modelDownloadFailed:
            return "言語モデルのダウンロードに失敗しました"
        case .initializationFailed:
            return "文字起こしの初期化に失敗しました"
        case .alreadyTranscribing:
            return "すでに文字起こし中です"
        case .notStarted:
            return "文字起こしが開始されていません"
        case .noAudioData:
            return "音声データがありません"
        case .audioConversionFailed:
            return "音声データの変換に失敗しました"
        case .recognitionFailed(let message):
            return "文字起こしエラー: \(message)"
        case .timeout:
            return "文字起こしがタイムアウトしました"
        case .permissionDenied:
            return "マイクまたは音声認識の権限がありません"
        case .configurationFailed:
            return "設定に失敗しました"
        }
    }
}
