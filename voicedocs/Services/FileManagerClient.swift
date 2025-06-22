//
//  FileManagerClient.swift
//  voicedocs
//
//  Created by Assistant on 2024/12/22.
//

import Foundation
import ComposableArchitecture
import os.log

// MARK: - File Manager Client Protocol
struct FileManagerClient {
    var createDirectory: @Sendable (URL) async throws -> Void
    var fileExists: @Sendable (UUID, FileType) async -> Bool
    var getFileURL: @Sendable (UUID, FileType) async -> URL?
    var getFileSize: @Sendable (UUID, FileType) async -> Int64?
    var deleteFile: @Sendable (UUID, FileType) async throws -> Void
    var moveFile: @Sendable (URL, UUID, FileType) async throws -> URL
    var copyFile: @Sendable (UUID, UUID, FileType) async throws -> Void
    var listFiles: @Sendable (FileType) async -> [FileInfo]
    var getDocumentsDirectory: @Sendable () async -> URL
    var getVoiceRecordingsDirectory: @Sendable () async -> URL
}

// MARK: - File Type Enum
enum FileType: String, CaseIterable {
    case recording = "recording"
    case segment = "segment"
    case backup = "backup"
    case temp = "temp"
    
    var fileExtension: String {
        switch self {
        case .recording, .segment:
            return "m4a"
        case .backup:
            return "backup"
        case .temp:
            return "tmp"
        }
    }
    
    var subdirectory: String {
        switch self {
        case .recording:
            return "VoiceRecordings"
        case .segment:
            return "VoiceRecordings/Segments"
        case .backup:
            return "Backups"
        case .temp:
            return "Temp"
        }
    }
}

// MARK: - File Info Structure
struct FileInfo: Equatable, Identifiable {
    let id: UUID
    let fileType: FileType
    let url: URL
    let size: Int64
    let createdAt: Date
    let modifiedAt: Date
}

// MARK: - File Manager Error
enum FileManagerError: LocalizedError, Equatable {
    case directoryCreationFailed(String)
    case fileNotFound(UUID, FileType)
    case fileMoveOperationFailed(String)
    case fileCopyOperationFailed(String)
    case fileDeletionFailed(String)
    case invalidFileURL(String)
    case documentDirectoryNotFound
    
    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path):
            return "ディレクトリの作成に失敗しました: \(path)"
        case .fileNotFound(let id, let type):
            return "ファイルが見つかりません: \(id.uuidString) (\(type.rawValue))"
        case .fileMoveOperationFailed(let reason):
            return "ファイルの移動に失敗しました: \(reason)"
        case .fileCopyOperationFailed(let reason):
            return "ファイルのコピーに失敗しました: \(reason)"
        case .fileDeletionFailed(let reason):
            return "ファイルの削除に失敗しました: \(reason)"
        case .invalidFileURL(let url):
            return "無効なファイルURL: \(url)"
        case .documentDirectoryNotFound:
            return "Documentsディレクトリが見つかりません"
        }
    }
}

// MARK: - Live Implementation
extension FileManagerClient {
    static let live = Self(
        createDirectory: { url in
            try await FileManagerService.shared.createDirectory(at: url)
        },
        fileExists: { id, type in
            await FileManagerService.shared.fileExists(id: id, type: type)
        },
        getFileURL: { id, type in
            await FileManagerService.shared.getFileURL(id: id, type: type)
        },
        getFileSize: { id, type in
            await FileManagerService.shared.getFileSize(id: id, type: type)
        },
        deleteFile: { id, type in
            try await FileManagerService.shared.deleteFile(id: id, type: type)
        },
        moveFile: { sourceURL, id, type in
            try await FileManagerService.shared.moveFile(from: sourceURL, to: id, type: type)
        },
        copyFile: { sourceId, destinationId, type in
            try await FileManagerService.shared.copyFile(from: sourceId, to: destinationId, type: type)
        },
        listFiles: { type in
            await FileManagerService.shared.listFiles(type: type)
        },
        getDocumentsDirectory: {
            await FileManagerService.shared.getDocumentsDirectory()
        },
        getVoiceRecordingsDirectory: {
            await FileManagerService.shared.getVoiceRecordingsDirectory()
        }
    )
}

// MARK: - Test Implementation
extension FileManagerClient {
    static let test = Self(
        createDirectory: { _ in },
        fileExists: { _, _ in true },
        getFileURL: { id, type in
            URL(fileURLWithPath: "/tmp/test-\(id.uuidString).\(type.fileExtension)")
        },
        getFileSize: { _, _ in 1024 },
        deleteFile: { _, _ in },
        moveFile: { _, id, type in
            URL(fileURLWithPath: "/tmp/moved-\(id.uuidString).\(type.fileExtension)")
        },
        copyFile: { _, _, _ in },
        listFiles: { _ in [] },
        getDocumentsDirectory: {
            URL(fileURLWithPath: "/tmp/Documents")
        },
        getVoiceRecordingsDirectory: {
            URL(fileURLWithPath: "/tmp/Documents/VoiceRecordings")
        }
    )
}

// MARK: - File Manager Service Implementation
@MainActor
class FileManagerService: ObservableObject {
    static let shared = FileManagerService()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Directory Operations
    
    func createDirectory(at url: URL) async throws {
        AppLogger.fileOperation.debug("Creating directory at: \(url.path)")
        
        guard !fileManager.fileExists(atPath: url.path) else {
            AppLogger.fileOperation.debug("Directory already exists: \(url.path)")
            return
        }
        
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            AppLogger.fileOperation.info("Successfully created directory: \(url.path)")
        } catch {
            AppLogger.fileOperation.error("Failed to create directory: \(error.localizedDescription)")
            throw FileManagerError.directoryCreationFailed(url.path)
        }
    }
    
    func getDocumentsDirectory() async -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            AppLogger.fileOperation.error("Documents directory not found")
            fatalError("Documents directory not accessible")
        }
        return documentsURL
    }
    
    func getVoiceRecordingsDirectory() async -> URL {
        let documentsURL = await getDocumentsDirectory()
        let voiceRecordingsURL = documentsURL.appendingPathComponent("VoiceRecordings")
        
        // ディレクトリが存在しない場合は作成
        do {
            try await createDirectory(at: voiceRecordingsURL)
        } catch {
            AppLogger.fileOperation.error("Failed to create VoiceRecordings directory: \(error.localizedDescription)")
        }
        
        return voiceRecordingsURL
    }
    
    // MARK: - File Path Generation
    
    private func getDirectoryURL(for type: FileType) async -> URL {
        let documentsURL = await getDocumentsDirectory()
        return documentsURL.appendingPathComponent(type.subdirectory)
    }
    
    private func generateFileName(id: UUID, type: FileType) -> String {
        switch type {
        case .recording:
            return "recording-\(id.uuidString).\(type.fileExtension)"
        case .segment:
            return "segment-\(id.uuidString).\(type.fileExtension)"
        case .backup:
            return "backup-\(id.uuidString).\(type.fileExtension)"
        case .temp:
            return "temp-\(id.uuidString).\(type.fileExtension)"
        }
    }
    
    // MARK: - File Operations
    
    func getFileURL(id: UUID, type: FileType) async -> URL? {
        let directoryURL = await getDirectoryURL(for: type)
        let fileName = generateFileName(id: id, type: type)
        let fileURL = directoryURL.appendingPathComponent(fileName)
        
        AppLogger.fileOperation.debug("Generated file URL: \(fileURL.path)")
        return fileURL
    }
    
    func fileExists(id: UUID, type: FileType) async -> Bool {
        guard let fileURL = await getFileURL(id: id, type: type) else {
            AppLogger.fileOperation.warning("Could not generate file URL for \(id.uuidString)")
            return false
        }
        
        let exists = fileManager.fileExists(atPath: fileURL.path)
        AppLogger.fileOperation.debug("File exists check for \(id.uuidString): \(exists)")
        return exists
    }
    
    func getFileSize(id: UUID, type: FileType) async -> Int64? {
        guard let fileURL = await getFileURL(id: id, type: type),
              fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.fileOperation.warning("File not found for size check: \(id.uuidString)")
            return nil
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            AppLogger.fileOperation.debug("File size for \(id.uuidString): \(fileSize) bytes")
            return fileSize
        } catch {
            AppLogger.fileOperation.error("Failed to get file size for \(id.uuidString): \(error.localizedDescription)")
            return nil
        }
    }
    
    func deleteFile(id: UUID, type: FileType) async throws {
        guard let fileURL = await getFileURL(id: id, type: type) else {
            throw FileManagerError.fileNotFound(id, type)
        }
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.fileOperation.warning("Attempted to delete non-existent file: \(id.uuidString)")
            return
        }
        
        do {
            try fileManager.removeItem(at: fileURL)
            AppLogger.fileOperation.info("Successfully deleted file: \(id.uuidString)")
        } catch {
            AppLogger.fileOperation.error("Failed to delete file: \(id.uuidString): \(error.localizedDescription)")
            throw FileManagerError.fileDeletionFailed(error.localizedDescription)
        }
    }
    
    func moveFile(from sourceURL: URL, to id: UUID, type: FileType) async throws -> URL {
        guard let destinationURL = await getFileURL(id: id, type: type) else {
            throw FileManagerError.invalidFileURL("Could not generate destination URL")
        }
        
        // 宛先ディレクトリを作成
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try await createDirectory(at: destinationDirectory)
        
        // 既存ファイルがあれば削除
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            AppLogger.fileOperation.info("Successfully moved file to: \(destinationURL.path)")
            return destinationURL
        } catch {
            AppLogger.fileOperation.error("Failed to move file: \(error.localizedDescription)")
            throw FileManagerError.fileMoveOperationFailed(error.localizedDescription)
        }
    }
    
    func copyFile(from sourceId: UUID, to destinationId: UUID, type: FileType) async throws {
        guard let sourceURL = await getFileURL(id: sourceId, type: type),
              let destinationURL = await getFileURL(id: destinationId, type: type) else {
            throw FileManagerError.invalidFileURL("Could not generate URLs for copy operation")
        }
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileManagerError.fileNotFound(sourceId, type)
        }
        
        // 宛先ディレクトリを作成
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try await createDirectory(at: destinationDirectory)
        
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            AppLogger.fileOperation.info("Successfully copied file from \(sourceId.uuidString) to \(destinationId.uuidString)")
        } catch {
            AppLogger.fileOperation.error("Failed to copy file: \(error.localizedDescription)")
            throw FileManagerError.fileCopyOperationFailed(error.localizedDescription)
        }
    }
    
    func listFiles(type: FileType) async -> [FileInfo] {
        let directoryURL = await getDirectoryURL(for: type)
        
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            AppLogger.fileOperation.debug("Directory does not exist: \(directoryURL.path)")
            return []
        }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
            
            let fileInfos: [FileInfo] = fileURLs.compactMap { url in
                guard let fileName = url.lastPathComponent.components(separatedBy: "-").last?.components(separatedBy: ".").first,
                      let id = UUID(uuidString: fileName.replacingOccurrences(of: "recording-", with: "").replacingOccurrences(of: "segment-", with: "").replacingOccurrences(of: "backup-", with: "").replacingOccurrences(of: "temp-", with: "")) else {
                    return nil
                }
                
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
                    
                    return FileInfo(
                        id: id,
                        fileType: type,
                        url: url,
                        size: Int64(resourceValues.fileSize ?? 0),
                        createdAt: resourceValues.creationDate ?? Date(),
                        modifiedAt: resourceValues.contentModificationDate ?? Date()
                    )
                } catch {
                    AppLogger.fileOperation.error("Failed to get file attributes for \(url.path): \(error.localizedDescription)")
                    return nil
                }
            }
            
            AppLogger.fileOperation.debug("Listed \(fileInfos.count) files of type \(type.rawValue)")
            return fileInfos.sorted { $0.createdAt > $1.createdAt }
            
        } catch {
            AppLogger.fileOperation.error("Failed to list files in directory: \(directoryURL.path): \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Dependency Key
private enum FileManagerClientKey: DependencyKey {
    static let liveValue = FileManagerClient.live
    static let testValue = FileManagerClient.test
}

extension DependencyValues {
    var fileManagerClient: FileManagerClient {
        get { self[FileManagerClientKey.self] }
        set { self[FileManagerClientKey.self] = newValue }
    }
}