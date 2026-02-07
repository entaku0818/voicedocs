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
