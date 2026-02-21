//
//  VoiceMemo.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation

struct VoiceMemo: Equatable {
    var id: UUID
    var title: String
    var text: String  // リアルタイム文字起こし（録音中の音声認識）
    var aiTranscriptionText: String = ""  // AI文字起こし（WhisperKit）
    var date: Date
    var segments: [AudioSegment] = []
    var videoFilePath: String?  // 動画ファイルのパス（動画インポート時のみ）

    // 文字起こし関連プロパティ
    var transcriptionStatus: TranscriptionStatus = .none
    var transcriptionQuality: Float = 0.0
    var transcribedAt: Date?
    var transcriptionError: String?
    
    // 全体の録音時間（メイン + セグメント）
    var totalDuration: TimeInterval {
        return segments.reduce(0) { $0 + $1.duration }
    }
    
    // セグメントを含むすべての音声ファイルパス
    var allAudioPaths: [String] {
        return segments.map { $0.filePath }.filter { !$0.isEmpty }
    }
    
    // 次のセグメント開始時間
    var nextSegmentStartTime: TimeInterval {
        guard let lastSegment = segments.max(by: { $0.endTime < $1.endTime }) else {
            return 0 // 最初のセグメント
        }
        return lastSegment.endTime
    }
    
    // 文字起こし状態の確認
    var isTranscriptionInProgress: Bool {
        return transcriptionStatus.isInProgress
    }
    
    var isTranscriptionCompleted: Bool {
        return transcriptionStatus.isCompleted
    }
    
    var hasTranscriptionFailed: Bool {
        return transcriptionStatus.hasFailed
    }
    
    // 文字起こし品質のパーセンテージ表示
    var transcriptionQualityPercentage: Int {
        return Int(transcriptionQuality * 100)
    }

    // 動画ファイルの有無
    var hasVideo: Bool {
        return videoFilePath != nil && !(videoFilePath?.isEmpty ?? true)
    }

    // 動画ファイルのURL
    var videoFileURL: URL? {
        guard let path = videoFilePath, !path.isEmpty else { return nil }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("VoiceRecordings").appendingPathComponent(path)
    }
}
