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
        voiceMemos.append(VoiceMemo(id: UUID(), title: "Memo 1", text: "This is the first memo.", date: Date(), filePath: "/path/to/file1"))
        voiceMemos.append(VoiceMemo(id: UUID(), title: "Memo 2", text: "This is the second memo.", date: Date().addingTimeInterval(-86400), filePath: "/path/to/file2"))
        voiceMemos.append(VoiceMemo(id: UUID(), title: "Memo 3", text: "This is the third memo.", date: Date().addingTimeInterval(-172800), filePath: "/path/to/file3"))
    }

    func saveVoiceMemo(title: String, text: String, filePath: String?) {
        let newMemo = VoiceMemo(id: UUID(), title: title, text: text, date: Date(), filePath: filePath ?? "")
        voiceMemos.append(newMemo)
    }

    func fetchVoiceMemos() -> [VoiceMemo] {
        return voiceMemos.sorted { $0.date > $1.date }
    }
    
    func deleteVoiceMemo(id: UUID) -> Bool {
        if let index = voiceMemos.firstIndex(where: { $0.id == id }) {
            voiceMemos.remove(at: index)
            return true
        }
        return false
    }
    
    func updateVoiceMemo(id: UUID, title: String?, text: String?) -> Bool {
        if let index = voiceMemos.firstIndex(where: { $0.id == id }) {
            var updatedMemo = voiceMemos[index]
            if let title = title {
                updatedMemo.title = title
            }
            if let text = text {
                updatedMemo.text = text
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
}
