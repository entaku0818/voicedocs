//
//  InputSourceManager.swift
//  voicedocs
//
//  Created by Claude on 2025/01/17.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Input Source Types

/// 入力ソースの種類
enum InputSourceType: String, CaseIterable {
    case recording = "recording"        // 録音（既存）
    case audioFile = "audioFile"        // 外部音声ファイル
    case videoFile = "videoFile"        // 動画ファイル
    case url = "url"                    // URL
    case image = "image"                // 画像OCR
    case pdf = "pdf"                    // PDF

    var displayName: String {
        switch self {
        case .recording: return "録音"
        case .audioFile: return "音声ファイル"
        case .videoFile: return "動画"
        case .url: return "URL"
        case .image: return "画像"
        case .pdf: return "PDF"
        }
    }

    var iconName: String {
        switch self {
        case .recording: return "mic.fill"
        case .audioFile: return "doc.fill"
        case .videoFile: return "film.fill"
        case .url: return "link"
        case .image: return "photo.fill"
        case .pdf: return "doc.text.fill"
        }
    }
}

// MARK: - Supported File Types

/// 対応音声フォーマット
struct SupportedAudioFormats {
    static let types: [UTType] = [
        .audio,
        .mpeg4Audio,  // m4a
        .mp3,
        .wav,
        .aiff
    ]

    static let extensions: [String] = ["m4a", "mp3", "wav", "aac", "aiff", "caf"]

    static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return extensions.contains(ext)
    }
}

/// 対応動画フォーマット
struct SupportedVideoFormats {
    static let types: [UTType] = [
        .movie,
        .mpeg4Movie,  // mp4
        .quickTimeMovie  // mov
    ]

    static let extensions: [String] = ["mp4", "mov", "m4v"]

    static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return extensions.contains(ext)
    }
}

// MARK: - Import Result

/// インポート結果
struct ImportResult {
    let sourceType: InputSourceType
    let originalURL: URL
    let processedURL: URL  // 処理用にコピーされたURL
    let fileName: String
    let fileSize: Int64
    let duration: TimeInterval?  // 音声/動画の長さ

    init(sourceType: InputSourceType, originalURL: URL, processedURL: URL) {
        self.sourceType = sourceType
        self.originalURL = originalURL
        self.processedURL = processedURL
        self.fileName = originalURL.lastPathComponent

        // ファイルサイズ取得
        let attributes = try? FileManager.default.attributesOfItem(atPath: processedURL.path)
        self.fileSize = attributes?[.size] as? Int64 ?? 0
        self.duration = nil
    }

    init(sourceType: InputSourceType, originalURL: URL, processedURL: URL, duration: TimeInterval?) {
        self.sourceType = sourceType
        self.originalURL = originalURL
        self.processedURL = processedURL
        self.fileName = originalURL.lastPathComponent

        let attributes = try? FileManager.default.attributesOfItem(atPath: processedURL.path)
        self.fileSize = attributes?[.size] as? Int64 ?? 0
        self.duration = duration
    }

    var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var durationString: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Input Source Manager

/// 入力ソース管理クラス
class InputSourceManager: ObservableObject {

    // MARK: - Published Properties
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var lastError: String?
    @Published var lastImportResult: ImportResult?

    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let importDirectory: URL

    // MARK: - Initialization

    init() {
        // インポートファイル用ディレクトリを作成
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        importDirectory = documentsPath.appendingPathComponent("Imports", isDirectory: true)

        if !fileManager.fileExists(atPath: importDirectory.path) {
            try? fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Audio File Import

    /// 音声ファイルをインポート
    func importAudioFile(from url: URL) async throws -> ImportResult {
        await MainActor.run {
            self.isImporting = true
            self.importProgress = 0
            self.lastError = nil
        }

        defer {
            Task { @MainActor in
                self.isImporting = false
            }
        }

        // ファイル形式チェック
        guard SupportedAudioFormats.isSupported(url: url) else {
            let error = "非対応の音声形式です: \(url.pathExtension)"
            await MainActor.run { self.lastError = error }
            throw InputSourceError.unsupportedFormat(url.pathExtension)
        }

        await MainActor.run { self.importProgress = 0.2 }

        // セキュリティスコープアクセス
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        // ファイルをインポートディレクトリにコピー
        let destFileName = "\(UUID().uuidString)_\(url.lastPathComponent)"
        let destURL = importDirectory.appendingPathComponent(destFileName)

        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: url, to: destURL)
        } catch {
            let errorMsg = "ファイルのコピーに失敗しました: \(error.localizedDescription)"
            await MainActor.run { self.lastError = errorMsg }
            throw InputSourceError.copyFailed(error.localizedDescription)
        }

        await MainActor.run { self.importProgress = 0.6 }

        // 音声の長さを取得
        let duration = try await getAudioDuration(url: destURL)

        await MainActor.run { self.importProgress = 1.0 }

        let result = ImportResult(
            sourceType: .audioFile,
            originalURL: url,
            processedURL: destURL,
            duration: duration
        )

        await MainActor.run {
            self.lastImportResult = result
        }

        return result
    }

    /// 音声の長さを取得
    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    // MARK: - Video File Import

    /// 動画ファイルから音声を抽出してインポート
    func importVideoFile(from url: URL) async throws -> ImportResult {
        await MainActor.run {
            self.isImporting = true
            self.importProgress = 0
            self.lastError = nil
        }

        defer {
            Task { @MainActor in
                self.isImporting = false
            }
        }

        // ファイル形式チェック
        guard SupportedVideoFormats.isSupported(url: url) else {
            let error = "非対応の動画形式です: \(url.pathExtension)"
            await MainActor.run { self.lastError = error }
            throw InputSourceError.unsupportedFormat(url.pathExtension)
        }

        await MainActor.run { self.importProgress = 0.1 }

        // セキュリティスコープアクセス
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        // 出力先の音声ファイルパス
        let audioFileName = "\(UUID().uuidString).m4a"
        let audioURL = importDirectory.appendingPathComponent(audioFileName)

        // 既存ファイルがあれば削除
        if fileManager.fileExists(atPath: audioURL.path) {
            try? fileManager.removeItem(at: audioURL)
        }

        await MainActor.run { self.importProgress = 0.2 }

        // AVAssetExportSessionで音声抽出
        let asset = AVURLAsset(url: url)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            let errorMsg = "音声抽出セッションの作成に失敗しました"
            await MainActor.run { self.lastError = errorMsg }
            throw InputSourceError.extractionFailed("ExportSession creation failed")
        }

        exportSession.outputURL = audioURL
        exportSession.outputFileType = .m4a

        await MainActor.run { self.importProgress = 0.4 }

        // 音声抽出を実行
        await exportSession.export()

        await MainActor.run { self.importProgress = 0.7 }

        // エクスポート結果をチェック
        guard exportSession.status == .completed else {
            let errorMsg: String
            if let error = exportSession.error {
                errorMsg = "音声抽出に失敗しました: \(error.localizedDescription)"
            } else {
                errorMsg = "音声抽出に失敗しました: ステータス \(exportSession.status.rawValue)"
            }
            await MainActor.run { self.lastError = errorMsg }
            throw InputSourceError.extractionFailed(errorMsg)
        }

        // 音声ファイルが作成されたか確認
        guard fileManager.fileExists(atPath: audioURL.path) else {
            let errorMsg = "抽出された音声ファイルが見つかりません"
            await MainActor.run { self.lastError = errorMsg }
            throw InputSourceError.extractionFailed(errorMsg)
        }

        await MainActor.run { self.importProgress = 0.9 }

        // 音声の長さを取得
        let duration = try await getAudioDuration(url: audioURL)

        await MainActor.run { self.importProgress = 1.0 }

        let result = ImportResult(
            sourceType: .videoFile,
            originalURL: url,
            processedURL: audioURL,
            duration: duration
        )

        await MainActor.run {
            self.lastImportResult = result
        }

        return result
    }

    // MARK: - URL Audio Download

    /// URLから音声ファイルをダウンロード
    func downloadAudioFromURL(_ urlString: String, progressHandler: @escaping (Double) -> Void) async throws -> ImportResult {
        await MainActor.run {
            self.isImporting = true
            self.importProgress = 0
            self.lastError = nil
        }

        defer {
            Task { @MainActor in
                self.isImporting = false
            }
        }

        // URL検証
        guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else {
            let error = "無効なURLです"
            await MainActor.run { self.lastError = error }
            throw InputSourceError.downloadFailed(error)
        }

        await MainActor.run { self.importProgress = 0.05 }
        progressHandler(0.05)

        // ファイル拡張子を取得（URLパスまたはContent-Typeから）
        var fileExtension = url.pathExtension.lowercased()
        if fileExtension.isEmpty || !SupportedAudioFormats.extensions.contains(fileExtension) {
            // デフォルトでm4aを使用
            fileExtension = "m4a"
        }

        // ダウンロード先ファイル名
        let destFileName = "\(UUID().uuidString).\(fileExtension)"
        let destURL = importDirectory.appendingPathComponent(destFileName)

        // 既存ファイルがあれば削除
        if fileManager.fileExists(atPath: destURL.path) {
            try? fileManager.removeItem(at: destURL)
        }

        // URLSessionでダウンロード（プログレス付き）
        let (tempURL, response) = try await downloadWithProgress(from: url, progressHandler: progressHandler)

        // HTTPレスポンス確認
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                let error = "サーバーエラー: HTTP \(httpResponse.statusCode)"
                await MainActor.run { self.lastError = error }
                throw InputSourceError.downloadFailed(error)
            }

            // Content-Typeから拡張子を推測
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                let detectedExtension = extensionFromContentType(contentType)
                if !detectedExtension.isEmpty && detectedExtension != fileExtension {
                    fileExtension = detectedExtension
                }
            }
        }

        // ファイルを移動
        let finalFileName = "\(UUID().uuidString).\(fileExtension)"
        let finalURL = importDirectory.appendingPathComponent(finalFileName)

        do {
            try fileManager.moveItem(at: tempURL, to: finalURL)
        } catch {
            let errorMsg = "ファイルの保存に失敗しました: \(error.localizedDescription)"
            await MainActor.run { self.lastError = errorMsg }
            throw InputSourceError.copyFailed(errorMsg)
        }

        await MainActor.run { self.importProgress = 0.9 }
        progressHandler(0.9)

        // ダウンロードしたファイルが音声かどうか確認
        let isValidAudio = await validateAudioFile(at: finalURL)
        if !isValidAudio {
            try? fileManager.removeItem(at: finalURL)
            let error = "ダウンロードしたファイルは有効な音声ファイルではありません"
            await MainActor.run { self.lastError = error }
            throw InputSourceError.unsupportedFormat("invalid audio")
        }

        // 音声の長さを取得
        let duration = try await getAudioDuration(url: finalURL)

        await MainActor.run { self.importProgress = 1.0 }
        progressHandler(1.0)

        let result = ImportResult(
            sourceType: .url,
            originalURL: url,
            processedURL: finalURL,
            duration: duration
        )

        await MainActor.run {
            self.lastImportResult = result
        }

        return result
    }

    /// URLからダウンロード（プログレス付き）
    private func downloadWithProgress(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: InputSourceError.downloadFailed(error.localizedDescription))
                    return
                }

                guard let tempURL = tempURL, let response = response else {
                    continuation.resume(throwing: InputSourceError.downloadFailed("ダウンロードに失敗しました"))
                    return
                }

                // 一時ファイルをコピー（ダウンロード完了後すぐ消えるため）
                let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: tempURL, to: tempCopy)
                    continuation.resume(returning: (tempCopy, response))
                } catch {
                    continuation.resume(throwing: InputSourceError.copyFailed(error.localizedDescription))
                }
            }

            // プログレス観察
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                // ダウンロードは全体の80%
                let downloadProgress = 0.1 + (progress.fractionCompleted * 0.8)
                progressHandler(downloadProgress)
                Task { @MainActor in
                    self.importProgress = downloadProgress
                }
            }

            // 観察を保持（タスク完了まで）
            objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

            task.resume()
        }
    }

    /// Content-Typeから拡張子を推測
    private func extensionFromContentType(_ contentType: String) -> String {
        let type = contentType.lowercased()
        if type.contains("audio/mpeg") || type.contains("audio/mp3") {
            return "mp3"
        } else if type.contains("audio/m4a") || type.contains("audio/x-m4a") {
            return "m4a"
        } else if type.contains("audio/wav") || type.contains("audio/x-wav") {
            return "wav"
        } else if type.contains("audio/aac") {
            return "aac"
        } else if type.contains("audio/aiff") {
            return "aiff"
        } else if type.contains("audio/mp4") || type.contains("audio/mpeg4") {
            return "m4a"
        }
        return ""
    }

    /// 音声ファイルの有効性を確認
    private func validateAudioFile(at url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Cleanup

    /// インポートファイルを削除
    func deleteImportedFile(at url: URL) {
        try? fileManager.removeItem(at: url)
    }

    /// 古いインポートファイルをクリーンアップ（24時間以上前）
    func cleanupOldImports() {
        guard let files = try? fileManager.contentsOfDirectory(at: importDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24時間前

        for fileURL in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < cutoffDate {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}

// MARK: - Errors

enum InputSourceError: LocalizedError {
    case unsupportedFormat(String)
    case copyFailed(String)
    case downloadFailed(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "非対応のファイル形式です: \(format)"
        case .copyFailed(let reason):
            return "ファイルのコピーに失敗しました: \(reason)"
        case .downloadFailed(let reason):
            return "ダウンロードに失敗しました: \(reason)"
        case .extractionFailed(let reason):
            return "音声抽出に失敗しました: \(reason)"
        }
    }
}
