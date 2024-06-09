

import Foundation
import CoreData

struct VoiceMemoController {
    static let shared = VoiceMemoController()

    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "voiceMemo")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
    }

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    // 音声メモの保存処理
    func saveVoiceMemo(title: String, text: String, filePath: String?) {
        let context = container.viewContext
        let voiceMemo = VoiceMemoModel(context: context)
        voiceMemo.id = UUID()
        voiceMemo.title = title
        voiceMemo.text = text
        voiceMemo.createdAt = Date()
        voiceMemo.voiceFilePath = filePath

        do {
            try context.save()
        } catch {
            print("Failed to save voice memo: \(error)")
        }
    }

    // 音声メモの一覧取得処理
    func fetchVoiceMemos() -> [VoiceMemo] {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()

        do {
            let voiceMemos = try context.fetch(fetchRequest)
            return voiceMemos.map { memo in
                VoiceMemo(
                    id: memo.id ?? UUID(),
                    title: memo.title ?? "",
                    text: memo.text ?? "",
                    date: memo.createdAt ?? Date(),
                    filePath: memo.voiceFilePath
                )
            }
        } catch {
            print("Failed to fetch voice memos: \(error)")
            return []
        }
    }
}
