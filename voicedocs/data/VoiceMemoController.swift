

import Foundation
import CoreData
import AVFoundation
import os.log


protocol VoiceMemoControllerProtocol {
    func saveVoiceMemo(id: UUID?, title: String, text: String, filePath: String?, videoFilePath: String?)
    func fetchVoiceMemos() -> [VoiceMemo]
    func fetchVoiceMemo(id: UUID) -> VoiceMemo?
    func deleteVoiceMemo(id: UUID) async -> Bool
    func updateVoiceMemo(id: UUID, title: String?, text: String?, aiTranscriptionText: String?, videoFilePath: String?) -> Bool
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
    private let fileManagerClient: FileManagerClient

    init() {
        // Live実装を直接使用（shared singletonパターンのため）
        self.fileManagerClient = FileManagerClient.live
        container = NSPersistentContainer(name: "VoiceMemoModel")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        // マイグレーションは不要（voiceFilePathを使用しないため）
        // migrateExistingFilesToVoiceRecordingsDirectory()
    }
    
    // UUIDから音声ファイルパスを解決するヘルパーメソッド
    private func getVoiceFilePath(for memoId: UUID) async -> String? {
        guard let fileURL = await fileManagerClient.getFileURL(memoId, .recording) else {
            AppLogger.fileOperation.warning("Could not get file URL for memo: \(memoId.uuidString)")
            return nil
        }
        return fileURL.path
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
    func saveVoiceMemo(id: UUID? = nil, title: String, text: String, filePath: String?, videoFilePath: String? = nil) {
        let context = container.viewContext
        let voiceMemo = VoiceMemoModel(context: context)
        voiceMemo.id = id ?? UUID() // 指定されたIDを使用、なければ新規生成
        voiceMemo.title = title
        voiceMemo.text = text
        voiceMemo.createdAt = Date()
        voiceMemo.videoFilePath = videoFilePath
        // voiceFilePathは削除予定のため設定しない

        do {
            try context.save()
        } catch {
            AppLogger.persistence.error("Failed to save voice memo: \(error.localizedDescription)")
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
                let memoId = memo.id ?? UUID()
                var voiceMemo = VoiceMemo(
                    id: memoId,
                    title: memo.title ?? "",
                    text: memo.text ?? "",
                    aiTranscriptionText: memo.aiTranscriptionText ?? "",
                    date: memo.createdAt ?? Date()
                )

                // 動画ファイルパスを復元
                voiceMemo.videoFilePath = memo.videoFilePath

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
                        AppLogger.persistence.error("Failed to decode segments: \(error.localizedDescription)")
                    }
                }

                return voiceMemo
            }
        } catch {
            AppLogger.persistence.error("Failed to fetch voice memos: \(error.localizedDescription)")
            return []
        }
    }
    
    // 音声メモの削除処理
    func deleteVoiceMemo(id: UUID) async -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                AppLogger.persistence.warning("Voice memo not found for deletion")
                return false
            }
            
            // 音声ファイルも削除（UUIDから解決）
            if let memoId = voiceMemo.id {
                if let filePath = await getVoiceFilePath(for: memoId) {
                    _ = deleteAudioFile(filePath: filePath)
                } else {
                    // UUID-basedの新しい削除メソッドを使用
                    _ = await deleteAudioFileById(memoId)
                }
            }
            
            context.delete(voiceMemo)
            try context.save()
            return true
        } catch {
            AppLogger.persistence.error("Failed to delete voice memo: \(error.localizedDescription)")
            return false
        }
    }
    
    // 音声メモの更新処理
    func updateVoiceMemo(id: UUID, title: String?, text: String?, aiTranscriptionText: String? = nil, videoFilePath: String? = nil) -> Bool {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let voiceMemo = voiceMemos.first else {
                AppLogger.persistence.warning("Voice memo not found for update")
                return false
            }

            if let title = title {
                voiceMemo.title = title
            }
            if let text = text {
                voiceMemo.text = text
            }
            if let aiTranscriptionText = aiTranscriptionText {
                voiceMemo.aiTranscriptionText = aiTranscriptionText
            }
            if let videoFilePath = videoFilePath {
                voiceMemo.videoFilePath = videoFilePath
            }
            
            try context.save()
            return true
        } catch {
            AppLogger.persistence.error("Failed to update voice memo: \(error.localizedDescription)")
            return false
        }
    }
    
    // ファイルサイズの取得
    func getFileSize(filePath: String) -> Int64? {
        // レガシーサポート - 新しい実装ではUUID-basedのgetFileSizeByIdを使用
        guard !filePath.isEmpty else { return nil }
        
        let fileURL = URL(fileURLWithPath: filePath)
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            return attributes[.size] as? Int64
        } catch {
            AppLogger.fileOperation.error("Failed to get file size: \(error.localizedDescription)")
            return nil
        }
    }
    
    // UUIDベースのファイルサイズ取得
    func getFileSizeById(_ memoId: UUID) async -> Int64? {
        return await fileManagerClient.getFileSize(memoId, .recording)
    }
    
    // 音声ファイルの再生時間取得
    func getAudioDuration(filePath: String) -> TimeInterval? {
        // レガシーサポート - 新しい実装ではUUID-basedのgetAudioDurationByIdを使用
        guard !filePath.isEmpty else { return nil }
        
        let fileURL = URL(fileURLWithPath: filePath)
        
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            return duration
        } catch {
            AppLogger.fileOperation.error("Failed to get audio duration: \(error.localizedDescription)")
            return nil
        }
    }
    
    // UUIDベースの音声ファイル再生時間取得
    func getAudioDurationById(_ memoId: UUID) async -> TimeInterval? {
        guard let fileURL = await fileManagerClient.getFileURL(memoId, .recording),
              await fileManagerClient.fileExists(memoId, .recording) else {
            AppLogger.fileOperation.warning("Audio file not found for memo: \(memoId.uuidString)")
            return nil
        }
        
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            AppLogger.fileOperation.debug("Audio duration for \(memoId.uuidString): \(duration) seconds")
            return duration
        } catch {
            AppLogger.fileOperation.error("Failed to get audio duration for \(memoId.uuidString): \(error.localizedDescription)")
            return nil
        }
    }
    
    // 音声ファイルの削除
    func deleteAudioFile(filePath: String) -> Bool {
        // レガシーサポート - 新しい実装ではUUID-basedのdeleteAudioFileByIdを使用
        guard !filePath.isEmpty else { return false }
        
        do {
            try FileManager.default.removeItem(atPath: filePath)
            return true
        } catch {
            AppLogger.fileOperation.error("Failed to delete audio file: \(error.localizedDescription)")
            return false
        }
    }
    
    // UUIDベースの音声ファイル削除
    func deleteAudioFileById(_ memoId: UUID) async -> Bool {
        do {
            try await fileManagerClient.deleteFile(memoId, .recording)
            AppLogger.fileOperation.info("Successfully deleted audio file for memo: \(memoId.uuidString)")
            return true
        } catch {
            AppLogger.fileOperation.error("Failed to delete audio file for \(memoId.uuidString): \(error.localizedDescription)")
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
                AppLogger.persistence.warning("Voice memo not found for adding segment")
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
            AppLogger.persistence.error("Failed to add segment: \(error.localizedDescription)")
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
                AppLogger.persistence.warning("Voice memo not found for removing segment")
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
            AppLogger.persistence.error("Failed to remove segment: \(error.localizedDescription)")
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
            AppLogger.persistence.error("Failed to get segments: \(error.localizedDescription)")
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
            AppLogger.persistence.error("Failed to update segment path: \(error.localizedDescription)")
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
                AppLogger.persistence.warning("Voice memo not found for transcription status update")
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
            AppLogger.persistence.error("Failed to update transcription status: \(error.localizedDescription)")
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
                AppLogger.persistence.warning("Voice memo not found for transcription result update")
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
            AppLogger.persistence.error("Failed to update transcription result: \(error.localizedDescription)")
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
                AppLogger.persistence.warning("Voice memo not found for transcription error update")
                return false
            }
            
            voiceMemo.transcriptionError = error
            voiceMemo.transcriptionStatus = TranscriptionStatus.failed.rawValue
            voiceMemo.transcribedAt = Date()
            
            try context.save()
            return true
        } catch {
            AppLogger.persistence.error("Failed to update transcription error: \(error.localizedDescription)")
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
            AppLogger.persistence.error("Failed to get transcription status: \(error.localizedDescription)")
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
                AppLogger.persistence.warning("Voice memo not found or has no text for filler word removal")
                return nil
            }
            
            let result = FillerWordRemover.shared.removeFillerWords(from: originalText, languages: languages)
            
            if result.hasChanges {
                voiceMemo.text = result.cleanedText
                try context.save()
            }
            
            return result
        } catch {
            AppLogger.persistence.error("Failed to remove filler words: \(error.localizedDescription)")
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
                AppLogger.persistence.warning("Voice memo not found or has no text for filler word preview")
                return nil
            }
            
            return FillerWordRemover.shared.removeFillerWords(from: originalText, languages: languages)
        } catch {
            AppLogger.persistence.error("Failed to preview filler word removal: \(error.localizedDescription)")
            return nil
        }
    }
    
    // 単一のボイスメモを取得
    func fetchVoiceMemo(id: UUID) -> VoiceMemo? {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<VoiceMemoModel> = VoiceMemoModel.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let voiceMemos = try context.fetch(fetchRequest)
            guard let memo = voiceMemos.first else {
                return nil
            }
            
            let memoId = memo.id ?? UUID()
            var voiceMemo = VoiceMemo(
                id: memoId,
                title: memo.title ?? "",
                text: memo.text ?? "",
                date: memo.createdAt ?? Date()
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
                    AppLogger.persistence.error("Failed to decode segments: \(error.localizedDescription)")
                }
            }
            
            return voiceMemo
        } catch {
            AppLogger.persistence.error("Failed to fetch voice memo: \(error.localizedDescription)")
            return nil
        }
    }
}
