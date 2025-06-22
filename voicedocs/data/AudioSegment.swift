//
//  AudioSegment.swift
//  voicedocs
//
//  Created by Claude on 2025/6/14.
//

import Foundation

struct AudioSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let filePath: String
    let startTime: TimeInterval
    let duration: TimeInterval
    let createdAt: Date
    
    init(id: UUID = UUID(), filePath: String, startTime: TimeInterval, duration: TimeInterval, createdAt: Date = Date()) {
        self.id = id
        self.filePath = filePath
        self.startTime = startTime
        self.duration = duration
        self.createdAt = createdAt
    }
}

extension AudioSegment {
    var endTime: TimeInterval {
        return startTime + duration
    }
    
    var index: Int {
        // ファイルパスから_segmentXの番号を抽出
        let components = filePath.components(separatedBy: "_segment")
        if components.count > 1,
           let segmentPart = components.last,
           let dotIndex = segmentPart.firstIndex(of: "."),
           let segmentNumber = Int(String(segmentPart[..<dotIndex])) {
            return segmentNumber
        }
        return 0
    }
}