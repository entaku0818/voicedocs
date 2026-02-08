//
//  FakeVoiceMemoController.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation
class FakeVoiceMemoController: VoiceMemoControllerProtocol {
    var voiceMemos: [VoiceMemo] = []

    init() {
        // 適当なデータを追加
        var memo1 = VoiceMemo(id: UUID(), title: "Memo 1", text: "This is the first memo.", aiTranscriptionText: "This is AI transcription for memo 1.", date: Date())
        memo1.transcriptionStatus = .completed
        memo1.transcriptionQuality = 0.85
        memo1.transcribedAt = Date().addingTimeInterval(-100)
        voiceMemos.append(memo1)
        
        var memo2 = VoiceMemo(id: UUID(), title: "Memo 2", text: "This is the second memo.", aiTranscriptionText: "This is AI transcription for memo 2.", date: Date().addingTimeInterval(-86400))
        memo2.transcriptionStatus = .completed
        memo2.transcriptionQuality = 0.92
        memo2.transcribedAt = Date().addingTimeInterval(-86300)
        voiceMemos.append(memo2)
        
        var memo3 = VoiceMemo(id: UUID(), title: "Memo 3", text: "This is the third memo.", aiTranscriptionText: "", date: Date().addingTimeInterval(-172800))
        memo3.transcriptionStatus = .none
        voiceMemos.append(memo3)
    }

    func saveVoiceMemo(id: UUID? = nil, title: String, text: String, filePath: String?, videoFilePath: String? = nil) {
        var newMemo = VoiceMemo(id: id ?? UUID(), title: title, text: text, aiTranscriptionText: "", date: Date())
        newMemo.videoFilePath = videoFilePath
        newMemo.transcriptionStatus = text.isEmpty ? .none : .completed
        newMemo.transcriptionQuality = text.isEmpty ? 0.0 : 0.8
        newMemo.transcribedAt = text.isEmpty ? nil : Date()
        voiceMemos.append(newMemo)
    }

    func fetchVoiceMemos() -> [VoiceMemo] {
        return voiceMemos.sorted { $0.date > $1.date }
    }
    
    func fetchVoiceMemo(id: UUID) -> VoiceMemo? {
        return voiceMemos.first(where: { $0.id == id })
    }
    
    func deleteVoiceMemo(id: UUID) async -> Bool {
        if let index = voiceMemos.firstIndex(where: { $0.id == id }) {
            voiceMemos.remove(at: index)
            return true
        }
        return false
    }
    
    func updateVoiceMemo(id: UUID, title: String?, text: String?, aiTranscriptionText: String? = nil, videoFilePath: String? = nil) -> Bool {
        if let index = voiceMemos.firstIndex(where: { $0.id == id }) {
            var updatedMemo = voiceMemos[index]
            if let title = title {
                updatedMemo.title = title
            }
            if let text = text {
                updatedMemo.text = text
            }
            if let aiTranscriptionText = aiTranscriptionText {
                updatedMemo.aiTranscriptionText = aiTranscriptionText
            }
            if let videoFilePath = videoFilePath {
                updatedMemo.videoFilePath = videoFilePath
            }
            voiceMemos[index] = updatedMemo
            return true
        }
        return false
    }
    
    func getFileSize(filePath: String) -> Int64? {
        // フェイクデータとして適当なサイズを返す
        return Int64.random(in: 1024...10485760) // 1KB - 10MB
    }
    
    func getAudioDuration(filePath: String) -> TimeInterval? {
        // フェイクデータとして適当な時間を返す
        return TimeInterval.random(in: 30...600) // 30秒 - 10分
    }
    
    func deleteAudioFile(filePath: String) -> Bool {
        // フェイクなので常にtrueを返す
        return true
    }
    
    // MARK: - セグメント管理機能
    
    func addSegmentToMemo(memoId: UUID, segment: AudioSegment) -> Bool {
        if let index = voiceMemos.firstIndex(where: { $0.id == memoId }) {
            voiceMemos[index].segments.append(segment)
            return true
        }
        return false
    }
    
    func removeSegmentFromMemo(memoId: UUID, segmentId: UUID) -> Bool {
        if let memoIndex = voiceMemos.firstIndex(where: { $0.id == memoId }) {
            voiceMemos[memoIndex].segments.removeAll { $0.id == segmentId }
            return true
        }
        return false
    }
    
    func getSegmentsForMemo(memoId: UUID) -> [AudioSegment] {
        if let memo = voiceMemos.first(where: { $0.id == memoId }) {
            return memo.segments
        }
        return []
    }
    
    func generateSegmentFilePath(memoId: UUID, segmentIndex: Int) -> String {
        return "/fake/path/\(memoId.uuidString)_segment\(segmentIndex).m4a"
    }
    
    // MARK: - 文字起こし関連機能
    
    func updateTranscriptionStatus(memoId: UUID, status: TranscriptionStatus) -> Bool {
        if let index = voiceMemos.firstIndex(where: { $0.id == memoId }) {
            voiceMemos[index].transcriptionStatus = status
            if status == .completed || status == .failed {
                voiceMemos[index].transcribedAt = Date()
            }
            if status == .inProgress {
                voiceMemos[index].transcriptionError = nil
            }
            return true
        }
        return false
    }
    
    func updateTranscriptionResult(memoId: UUID, text: String, quality: Float) -> Bool {
        if let index = voiceMemos.firstIndex(where: { $0.id == memoId }) {
            voiceMemos[index].text = text
            voiceMemos[index].transcriptionQuality = quality
            voiceMemos[index].transcriptionStatus = .completed
            voiceMemos[index].transcribedAt = Date()
            voiceMemos[index].transcriptionError = nil
            return true
        }
        return false
    }
    
    func updateTranscriptionError(memoId: UUID, error: String) -> Bool {
        if let index = voiceMemos.firstIndex(where: { $0.id == memoId }) {
            voiceMemos[index].transcriptionError = error
            voiceMemos[index].transcriptionStatus = .failed
            voiceMemos[index].transcribedAt = Date()
            return true
        }
        return false
    }
    
    func getTranscriptionStatus(memoId: UUID) -> TranscriptionStatus? {
        if let memo = voiceMemos.first(where: { $0.id == memoId }) {
            return memo.transcriptionStatus
        }
        return TranscriptionStatus.none
    }
    
    // MARK: - フィラーワード除去機能
    
    func removeFillerWordsFromMemo(memoId: UUID, languages: [FillerWordLanguage] = FillerWordLanguage.allCases) -> FillerWordRemovalResult? {
        if let index = voiceMemos.firstIndex(where: { $0.id == memoId }) {
            let originalText = voiceMemos[index].text
            let result = FillerWordRemover.shared.removeFillerWords(from: originalText, languages: languages)
            
            if result.hasChanges {
                voiceMemos[index].text = result.cleanedText
            }
            
            return result
        }
        return nil
    }
    
    func previewFillerWordRemoval(memoId: UUID, languages: [FillerWordLanguage] = FillerWordLanguage.allCases) -> FillerWordRemovalResult? {
        if let memo = voiceMemos.first(where: { $0.id == memoId }) {
            return FillerWordRemover.shared.removeFillerWords(from: memo.text, languages: languages)
        }
        return nil
    }
}
