

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
    
    // 文字起こし関連機能
    func updateTranscriptionStatus(memoId: UUID, status: TranscriptionStatus) -> Bool
    func updateTranscriptionResult(memoId: UUID, text: String, quality: Float) -> Bool
    func updateTranscriptionError(memoId: UUID, error: String) -> Bool
    func getTranscriptionStatus(memoId: UUID) -> TranscriptionStatus?
    
    // フィラーワード除去機能
    func removeFillerWordsFromMemo(memoId: UUID, languages: [FillerWordLanguage]) -> FillerWordRemovalResult?
    func previewFillerWordRemoval(memoId: UUID, languages: [FillerWordLanguage]) -> FillerWordRemovalResult?
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
        migrateExistingFilesToVoiceRecordingsDirectory()
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
                
                // 文字起こし関連情報を復元
                if let statusString = memo.transcriptionStatus {
                    voiceMemo.transcriptionStatus = TranscriptionStatus(rawValue: statusString) ?? .none
                }
                voiceMemo.transcriptionQuality = memo.transcriptionQuality
                voiceMemo.transcribedAt = memo.transcribedAt
                voiceMemo.transcriptionError = memo.transcriptionError
                
                // セグメント情報を復元
                if let segmentsData = memo.segments {
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
        let voiceRecordingsPath = documentsPath.appendingPathComponent("VoiceRecordings")
        
        // ディレクトリが存在しない場合は作成
        if !FileManager.default.fileExists(atPath: voiceRecordingsPath.path) {
            try? FileManager.default.createDirectory(at: voiceRecordingsPath, withIntermediateDirectories: true, attributes: nil)
        }
        
        let segmentFileName = "\(memoId.uuidString)_segment\(segmentIndex).m4a"
        return voiceRecordingsPath.appendingPathComponent(segmentFileName).path
    }
    
    // 既存のファイルをVoiceRecordingsディレクトリに移行
    private func migrateExistingFilesToVoiceRecordingsDirectory() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let voiceRecordingsPath = documentsPath.appendingPathComponent("VoiceRecordings")
        
        // VoiceRecordingsディレクトリを作成
        if !FileManager.default.fileExists(atPath: voiceRecordingsPath.path) {
            try? FileManager.default.createDirectory(at: voiceRecordingsPath, withIntermediateDirectories: true, attributes: nil)
        }
        
        // すべてのメモを取得
        let memos = fetchVoiceMemos()
        
        for memo in memos {
            // ファイルパスが存在し、まだ移行されていない場合
            if !memo.filePath.isEmpty,
               !memo.filePath.contains("VoiceRecordings") {
                
                let oldURL = URL(fileURLWithPath: memo.filePath)
                let fileName = oldURL.lastPathComponent
                let newURL = voiceRecordingsPath.appendingPathComponent(fileName)
                
                // ファイルが存在する場合のみ移動
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    do {
                        try FileManager.default.moveItem(at: oldURL, to: newURL)
                        // Core Dataのパスを更新
                        _ = updateVoiceMemoFilePath(id: memo.id, newPath: newURL.path)
                    } catch {
                        print("Failed to migrate file: \(error)")
                    }
                }
            }
            
            // セグメントも移行
            for segment in memo.segments {
                if !segment.filePath.contains("VoiceRecordings") {
                    let oldURL = URL(fileURLWithPath: segment.filePath)
                    let fileName = oldURL.lastPathComponent
                    let newURL = voiceRecordingsPath.appendingPathComponent(fileName)
                    
                    if FileManager.default.fileExists(atPath: oldURL.path) {
                        do {
                            try FileManager.default.moveItem(at: oldURL, to: newURL)
                            // セグメントのパスを更新
                            _ = updateSegmentFilePath(memoId: memo.id, segmentId: segment.id, newPath: newURL.path)
                        } catch {
                            print("Failed to migrate segment: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    // ファイルパスを更新するヘルパーメソッド
    private func updateVoiceMemoFilePath(id: UUID, newPath: String) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            if let memo = results.first {
                memo.voiceFilePath = newPath
                try context.save()
                return true
            }
        } catch {
            print("Failed to update file path: \(error)")
        }
        return false
    }
    
    // セグメントファイルパスを更新するヘルパーメソッド
    private func updateSegmentFilePath(memoId: UUID, segmentId: UUID, newPath: String) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            if let memo = results.first,
               let segmentsData = memo.segments,
               var segments = try? JSONDecoder().decode([AudioSegment].self, from: segmentsData) {
                
                if let index = segments.firstIndex(where: { $0.id == segmentId }) {
                    let oldSegment = segments[index]
                    let updatedSegment = AudioSegment(
                        id: oldSegment.id,
                        filePath: newPath,
                        startTime: oldSegment.startTime,
                        duration: oldSegment.duration,
                        createdAt: oldSegment.createdAt
                    )
                    segments[index] = updatedSegment
                    memo.segments = try? JSONEncoder().encode(segments)
                    try context.save()
                    return true
                }
            }
        } catch {
            print("Failed to update segment path: \(error)")
        }
        return false
    }
    
    // MARK: - 文字起こし関連機能
    
    // 文字起こし状態を更新
    func updateTranscriptionStatus(memoId: UUID, status: TranscriptionStatus) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                print("Voice memo not found for transcription status update")
                return false
            }
            
            voiceMemo.transcriptionStatus = status.rawValue
            
            // 完了または失敗時にタイムスタンプを記録
            if status == .completed || status == .failed {
                voiceMemo.transcribedAt = Date()
            }
            
            // 進行中にセットする場合はエラーをクリア
            if status == .inProgress {
                voiceMemo.transcriptionError = nil
            }
            
            try context.save()
            return true
        } catch {
            print("Failed to update transcription status: \(error)")
            return false
        }
    }
    
    // 文字起こし結果を更新
    func updateTranscriptionResult(memoId: UUID, text: String, quality: Float) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                print("Voice memo not found for transcription result update")
                return false
            }
            
            voiceMemo.text = text
            voiceMemo.transcriptionQuality = quality
            voiceMemo.transcriptionStatus = TranscriptionStatus.completed.rawValue
            voiceMemo.transcribedAt = Date()
            voiceMemo.transcriptionError = nil
            
            try context.save()
            return true
        } catch {
            print("Failed to update transcription result: \(error)")
            return false
        }
    }
    
    // 文字起こしエラーを更新
    func updateTranscriptionError(memoId: UUID, error: String) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                print("Voice memo not found for transcription error update")
                return false
            }
            
            voiceMemo.transcriptionError = error
            voiceMemo.transcriptionStatus = TranscriptionStatus.failed.rawValue
            voiceMemo.transcribedAt = Date()
            
            try context.save()
            return true
        } catch {
            print("Failed to update transcription error: \(error)")
            return false
        }
    }
    
    // 文字起こし状態を取得
    func getTranscriptionStatus(memoId: UUID) -> TranscriptionStatus? {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first,
                  let statusString = voiceMemo.transcriptionStatus else {
                return .none
            }
            
            return TranscriptionStatus(rawValue: statusString) ?? .none
        } catch {
            print("Failed to get transcription status: \(error)")
            return .none
        }
    }
    
    // MARK: - フィラーワード除去機能
    
    // フィラーワードを除去してメモを更新
    func removeFillerWordsFromMemo(memoId: UUID, languages: [FillerWordLanguage] = FillerWordLanguage.allCases) -> FillerWordRemovalResult? {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first,
                  let originalText = voiceMemo.text else {
                print("Voice memo not found or has no text for filler word removal")
                return nil
            }
            
            let result = FillerWordRemover.shared.removeFillerWords(from: originalText, languages: languages)
            
            if result.hasChanges {
                voiceMemo.text = result.cleanedText
                try context.save()
            }
            
            return result
        } catch {
            print("Failed to remove filler words: \(error)")
            return nil
        }
    }
    
    // フィラーワード除去のプレビュー（実際には更新しない）
    func previewFillerWordRemoval(memoId: UUID, languages: [FillerWordLanguage] = FillerWordLanguage.allCases) -> FillerWordRemovalResult? {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", memoId as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first,
                  let originalText = voiceMemo.text else {
                print("Voice memo not found or has no text for filler word preview")
                return nil
            }
            
            return FillerWordRemover.shared.removeFillerWords(from: originalText, languages: languages)
        } catch {
            print("Failed to preview filler word removal: \(error)")
            return nil
        }
    }
}
