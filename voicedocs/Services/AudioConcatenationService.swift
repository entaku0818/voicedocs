//
//  AudioConcatenationService.swift
//  voicedocs
//
//  Created by Claude on 2026-02-18.
//

import Foundation
import AVFoundation
import Combine

/// 音声セグメント連結サービス
/// 複数の音声ファイルを1つのm4aファイルに連結します
@MainActor
final class AudioConcatenationService: ObservableObject {

    // MARK: - Published Properties

    /// 連結処理の進捗（0.0 ~ 1.0）
    @Published private(set) var progress: Double = 0.0

    /// 処理中フラグ
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Error Types

    enum ConcatenationError: LocalizedError {
        case noSegments
        case fileNotFound(String)
        case compositionFailed(String)
        case exportFailed(String)
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .noSegments:
                return "連結するセグメントがありません"
            case .fileNotFound(let path):
                return "音声ファイルが見つかりません: \(path)"
            case .compositionFailed(let message):
                return "音声合成に失敗しました: \(message)"
            case .exportFailed(let message):
                return "ファイル出力に失敗しました: \(message)"
            case .unknown(let message):
                return "不明なエラー: \(message)"
            }
        }
    }

    // MARK: - Public Methods

    /// 複数のセグメントを連結して1つの音声ファイルを作成
    /// - Parameters:
    ///   - segments: 連結する音声セグメント（時系列順）
    ///   - outputFileName: 出力ファイル名（省略時は自動生成）
    /// - Returns: 連結された音声ファイルのURL（temporaryDirectory内）
    func concatenateSegments(
        _ segments: [AudioSegment],
        outputFileName: String? = nil
    ) async throws -> URL {
        // セグメント数チェック
        guard !segments.isEmpty else {
            throw ConcatenationError.noSegments
        }

        // 処理開始
        isProcessing = true
        progress = 0.0
        defer {
            isProcessing = false
        }

        do {
            // Step 1: AVMutableComposition作成
            let composition = AVMutableComposition()
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ConcatenationError.compositionFailed("オーディオトラックの作成に失敗しました")
            }

            progress = 0.1

            // Step 2: 各セグメントを連結
            var insertTime = CMTime.zero
            let segmentCount = segments.count

            for (index, segment) in segments.enumerated() {
                // ファイル存在確認
                let fileURL = URL(fileURLWithPath: segment.filePath)
                guard FileManager.default.fileExists(atPath: segment.filePath) else {
                    throw ConcatenationError.fileNotFound(segment.filePath)
                }

                // AVURLAssetとして読み込み
                let asset = AVURLAsset(url: fileURL)
                guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw ConcatenationError.compositionFailed("セグメント \(index + 1) のオーディオトラックが見つかりません")
                }

                // トラックの時間範囲を取得
                let timeRange = try await assetTrack.load(.timeRange)

                // コンポジショントラックに挿入
                try compositionTrack.insertTimeRange(
                    timeRange,
                    of: assetTrack,
                    at: insertTime
                )

                // 次の挿入位置を更新
                insertTime = CMTimeAdd(insertTime, timeRange.duration)

                // 進捗更新（0.1 ~ 0.6）
                progress = 0.1 + (0.5 * Double(index + 1) / Double(segmentCount))
            }

            progress = 0.6

            // Step 3: エクスポート設定
            let fileName = outputFileName ?? "concatenated_\(UUID().uuidString).m4a"
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            // 既存ファイルがあれば削除
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                throw ConcatenationError.exportFailed("エクスポートセッションの作成に失敗しました")
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a

            progress = 0.7

            // Step 4: エクスポート実行
            await exportSession.export()

            progress = 0.9

            // Step 5: 結果チェック
            guard exportSession.status == .completed else {
                let errorMessage: String
                if let error = exportSession.error {
                    errorMessage = error.localizedDescription
                } else {
                    errorMessage = "ステータス: \(exportSession.status.rawValue)"
                }
                throw ConcatenationError.exportFailed(errorMessage)
            }

            // ファイル存在確認
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw ConcatenationError.exportFailed("出力ファイルが作成されませんでした")
            }

            progress = 1.0

            return outputURL

        } catch let error as ConcatenationError {
            throw error
        } catch {
            throw ConcatenationError.unknown(error.localizedDescription)
        }
    }

    /// 進捗をリセット
    func resetProgress() {
        progress = 0.0
    }
}
