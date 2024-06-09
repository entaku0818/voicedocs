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
        return voiceMemos
    }
}
