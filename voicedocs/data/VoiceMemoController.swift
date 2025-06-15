

import Foundation
import CoreData
import AVFoundation


protocol VoiceMemoControllerProtocol {
    func saveVoiceMemo(title: String, text: String, filePath: String?)
    func fetchVoiceMemos() -> [VoiceMemo]
    func deleteVoiceMemo(id: UUID) -> Bool
    func updateVoiceMemo(id: UUID, title: String?, text: String?) -> Bool
    func getFileSize(filePath: String) -> Int64?
    func getAudioDuration(filePath: String) -> TimeInterval?
    func deleteAudioFile(filePath: String) -> Bool
    
    // セグメント関連機能
    func addSegmentToMemo(memoId: UUID, segment: AudioSegment) -> Bool
    func removeSegmentFromMemo(memoId: UUID, segmentId: UUID) -> Bool
    func getSegmentsForMemo(memoId: UUID) -> [AudioSegment]
    func generateSegmentFilePath(memoId: UUID, segmentIndex: Int) -> String
}

struct VoiceMemoController:VoiceMemoControllerProtocol {
    static let shared = VoiceMemoController()

    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "VoiceMemoModel")
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
        
        // 作成日時で降順ソート
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let voiceMemos = try context.fetch(fetchRequest)
            return voiceMemos.map { memo in
                var voiceMemo = VoiceMemo(
                    id: memo.id ?? UUID(),
                    title: memo.title ?? "",
                    text: memo.text ?? "",
                    date: memo.createdAt ?? Date(),
                    filePath: memo.voiceFilePath ?? ""
                )
                
                // セグメント情報を復元
                if let segmentsData = memo.value(forKey: "segments") as? Data {
                    do {
                        let segments = try JSONDecoder().decode([AudioSegment].self, from: segmentsData)
                        voiceMemo.segments = segments
                    } catch {
                        print("Failed to decode segments: \(error)")
                    }
                }
                
                return voiceMemo
            }
        } catch {
            print("Failed to fetch voice memos: \(error)")
            return []
        }
    }
    
    // 音声メモの削除処理
    func deleteVoiceMemo(id: UUID) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                print("Voice memo not found for deletion")
                return false
            }
            
            // 音声ファイルも削除
            if let filePath = voiceMemo.voiceFilePath, !filePath.isEmpty {
                _ = deleteAudioFile(filePath: filePath)
            }
            
            context.delete(voiceMemo)
            try context.save()
            return true
        } catch {
            print("Failed to delete voice memo: \(error)")
            return false
        }
    }
    
    // 音声メモの更新処理
    func updateVoiceMemo(id: UUID, title: String?, text: String?) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                print("Voice memo not found for update")
                return false
            }
            
            if let title = title {
                voiceMemo.title = title
            }
            if let text = text {
                voiceMemo.text = text
            }
            
            try context.save()
            return true
        } catch {
            print("Failed to update voice memo: \(error)")
            return false
        }
    }
    
    // ファイルサイズの取得
    func getFileSize(filePath: String) -> Int64? {
        guard !filePath.isEmpty else { return nil }
        
        let fileURL = URL(fileURLWithPath: filePath)
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            return attributes[.size] as? Int64
        } catch {
            print("Failed to get file size: \(error)")
            return nil
        }
    }
    
    // 音声ファイルの再生時間取得
    func getAudioDuration(filePath: String) -> TimeInterval? {
        guard !filePath.isEmpty else { return nil }
        
        let fileURL = URL(fileURLWithPath: filePath)
        
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            return duration
        } catch {
            print("Failed to get audio duration: \(error)")
            return nil
        }
    }
    
    // 音声ファイルの削除
    func deleteAudioFile(filePath: String) -> Bool {
        guard !filePath.isEmpty else { return false }
        
        do {
            try FileManager.default.removeItem(atPath: filePath)
            return true
        } catch {
            print("Failed to delete audio file: \(error)")
            return false
        }
    }
    
    // MARK: - セグメント管理機能
    
    // メモにセグメントを追加
    func addSegmentToMemo(memoId: UUID, segment: AudioSegment) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                print("Voice memo not found for adding segment")
                return false
            }
            
            // 既存のセグメントを取得
            var segments: [AudioSegment] = []
            if let segmentsData = voiceMemo.value(forKey: "segments") as? Data {
                segments = (try? JSONDecoder().decode([AudioSegment].self, from: segmentsData)) ?? []
            }
            
            // 新しいセグメントを追加
            segments.append(segment)
            
            // セグメントをJSONエンコードして保存
            let segmentsData = try JSONEncoder().encode(segments)
            voiceMemo.setValue(segmentsData, forKey: "segments")
            
            try context.save()
            return true
        } catch {
            print("Failed to add segment: \(error)")
            return false
        }
    }
    
    // メモからセグメントを削除
    func removeSegmentFromMemo(memoId: UUID, segmentId: UUID) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                print("Voice memo not found for removing segment")
                return false
            }
            
            // 既存のセグメントを取得
            var segments: [AudioSegment] = []
            if let segmentsData = voiceMemo.value(forKey: "segments") as? Data {
                segments = (try? JSONDecoder().decode([AudioSegment].self, from: segmentsData)) ?? []
            }
            
            // 指定されたセグメントを削除
            segments.removeAll { $0.id == segmentId }
            
            // セグメントをJSONエンコードして保存
            let segmentsData = try JSONEncoder().encode(segments)
            voiceMemo.setValue(segmentsData, forKey: "segments")
            
            try context.save()
            return true
        } catch {
            print("Failed to remove segment: \(error)")
            return false
        }
    }
    
    // メモのセグメント一覧を取得
    func getSegmentsForMemo(memoId: UUID) -> [AudioSegment] {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                return []
            }
            
            if let segmentsData = voiceMemo.value(forKey: "segments") as? Data {
                return (try? JSONDecoder().decode([AudioSegment].self, from: segmentsData)) ?? []
            }
            
            return []
        } catch {
            print("Failed to get segments: \(error)")
            return []
        }
    }
    
    // セグメントファイルパスを生成
    func generateSegmentFilePath(memoId: UUID, segmentIndex: Int) -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let segmentFileName = "\(memoId.uuidString)_segment\(segmentIndex).m4a"
        return documentsPath.appendingPathComponent(segmentFileName).path
    }
}
