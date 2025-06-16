//
//  TranscriptionStatus.swift
//  voicedocs
//
//  Created by Claude on 2025/6/16.
//

import Foundation

enum TranscriptionStatus: String, CaseIterable {
    case none = "none"           // 文字起こし未実行
    case inProgress = "inProgress" // 文字起こし中
    case completed = "completed"   // 文字起こし完了
    case failed = "failed"         // 文字起こし失敗
    
    var displayName: String {
        switch self {
        case .none:
            return "未実行"
        case .inProgress:
            return "処理中"
        case .completed:
            return "完了"
        case .failed:
            return "失敗"
        }
    }
    
    var isInProgress: Bool {
        return self == .inProgress
    }
    
    var isCompleted: Bool {
        return self == .completed
    }
    
    var hasFailed: Bool {
        return self == .failed
    }
}