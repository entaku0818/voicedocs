//
//  VoiceMemo.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation

struct VoiceMemo {
    var id: UUID
    var title: String
    var text: String
    var date: Date
    var filePath: String
    var segments: [AudioSegment] = []
    
    // 全体の録音時間（メイン + セグメント）
    var totalDuration: TimeInterval {
        return segments.reduce(0) { $0 + $1.duration }
    }
    
    // セグメントを含むすべての音声ファイルパス
    var allAudioPaths: [String] {
        var paths = [filePath]
        paths.append(contentsOf: segments.map { $0.filePath })
        return paths.filter { !$0.isEmpty }
    }
    
    // 次のセグメント開始時間
    var nextSegmentStartTime: TimeInterval {
        guard let lastSegment = segments.max(by: { $0.endTime < $1.endTime }) else {
            return 0 // 最初のセグメント
        }
        return lastSegment.endTime
    }
}
