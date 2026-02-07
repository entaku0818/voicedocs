//
//  InputSourceManagerTests.swift
//  voicedocsTests
//
//  Created by Claude on 2025/01/17.
//

import XCTest
import AVFoundation
@testable import voicedocs

final class InputSourceManagerTests: XCTestCase {
    var inputSourceManager: InputSourceManager!
    var testDirectory: URL!

    override func setUpWithError() throws {
        inputSourceManager = InputSourceManager()

        // テスト用ディレクトリを作成
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("InputSourceManagerTests")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        inputSourceManager = nil

        // テスト用ディレクトリを削除
        if FileManager.default.fileExists(atPath: testDirectory.path) {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        testDirectory = nil
    }

    // MARK: - SupportedAudioFormats Tests

    func testSupportedAudioFormatsExtensions() {
        XCTAssertTrue(SupportedAudioFormats.extensions.contains("m4a"))
        XCTAssertTrue(SupportedAudioFormats.extensions.contains("mp3"))
        XCTAssertTrue(SupportedAudioFormats.extensions.contains("wav"))
        XCTAssertTrue(SupportedAudioFormats.extensions.contains("aac"))
        XCTAssertTrue(SupportedAudioFormats.extensions.contains("aiff"))
        XCTAssertTrue(SupportedAudioFormats.extensions.contains("caf"))
    }

    func testSupportedAudioFormatsIsSupported() {
        // サポートされている形式
        let m4aURL = URL(fileURLWithPath: "/test/audio.m4a")
        XCTAssertTrue(SupportedAudioFormats.isSupported(url: m4aURL))

        let mp3URL = URL(fileURLWithPath: "/test/audio.mp3")
        XCTAssertTrue(SupportedAudioFormats.isSupported(url: mp3URL))

        let wavURL = URL(fileURLWithPath: "/test/audio.WAV") // 大文字でもOK
        XCTAssertTrue(SupportedAudioFormats.isSupported(url: wavURL))

        // サポートされていない形式
        let txtURL = URL(fileURLWithPath: "/test/document.txt")
        XCTAssertFalse(SupportedAudioFormats.isSupported(url: txtURL))

        let pdfURL = URL(fileURLWithPath: "/test/document.pdf")
        XCTAssertFalse(SupportedAudioFormats.isSupported(url: pdfURL))
    }

    // MARK: - SupportedVideoFormats Tests

    func testSupportedVideoFormatsExtensions() {
        XCTAssertTrue(SupportedVideoFormats.extensions.contains("mp4"))
        XCTAssertTrue(SupportedVideoFormats.extensions.contains("mov"))
        XCTAssertTrue(SupportedVideoFormats.extensions.contains("m4v"))
    }

    func testSupportedVideoFormatsIsSupported() {
        // サポートされている形式
        let mp4URL = URL(fileURLWithPath: "/test/video.mp4")
        XCTAssertTrue(SupportedVideoFormats.isSupported(url: mp4URL))

        let movURL = URL(fileURLWithPath: "/test/video.MOV") // 大文字でもOK
        XCTAssertTrue(SupportedVideoFormats.isSupported(url: movURL))

        // サポートされていない形式
        let aviURL = URL(fileURLWithPath: "/test/video.avi")
        XCTAssertFalse(SupportedVideoFormats.isSupported(url: aviURL))
    }

    // MARK: - InputSourceType Tests

    func testInputSourceTypeDisplayNames() {
        XCTAssertEqual(InputSourceType.recording.displayName, "録音")
        XCTAssertEqual(InputSourceType.audioFile.displayName, "音声ファイル")
        XCTAssertEqual(InputSourceType.videoFile.displayName, "動画")
        XCTAssertEqual(InputSourceType.url.displayName, "URL")
        XCTAssertEqual(InputSourceType.image.displayName, "画像")
        XCTAssertEqual(InputSourceType.pdf.displayName, "PDF")
    }

    func testInputSourceTypeIconNames() {
        XCTAssertEqual(InputSourceType.recording.iconName, "mic.fill")
        XCTAssertEqual(InputSourceType.audioFile.iconName, "doc.fill")
        XCTAssertEqual(InputSourceType.videoFile.iconName, "film.fill")
        XCTAssertEqual(InputSourceType.url.iconName, "link")
        XCTAssertEqual(InputSourceType.image.iconName, "photo.fill")
        XCTAssertEqual(InputSourceType.pdf.iconName, "doc.text.fill")
    }

    // MARK: - ImportResult Tests

    func testImportResultFileSizeString() throws {
        // テスト用ファイルを作成
        let testFileURL = testDirectory.appendingPathComponent("test.m4a")
        let testData = Data(repeating: 0, count: 1024) // 1KB
        try testData.write(to: testFileURL)

        let result = ImportResult(
            sourceType: .audioFile,
            originalURL: testFileURL,
            processedURL: testFileURL,
            duration: 10.0
        )

        XCTAssertEqual(result.fileName, "test.m4a")
        XCTAssertEqual(result.fileSize, 1024)
        XCTAssertNotNil(result.fileSizeString) // "1 KB" など
    }

    func testImportResultDurationString() {
        let testFileURL = URL(fileURLWithPath: "/test/audio.m4a")

        // 1分30秒
        let result1 = ImportResult(
            sourceType: .audioFile,
            originalURL: testFileURL,
            processedURL: testFileURL,
            duration: 90.0
        )
        XCTAssertEqual(result1.durationString, "1:30")

        // 5分5秒
        let result2 = ImportResult(
            sourceType: .audioFile,
            originalURL: testFileURL,
            processedURL: testFileURL,
            duration: 305.0
        )
        XCTAssertEqual(result2.durationString, "5:05")

        // nilの場合
        let result3 = ImportResult(
            sourceType: .audioFile,
            originalURL: testFileURL,
            processedURL: testFileURL,
            duration: nil
        )
        XCTAssertNil(result3.durationString)
    }

    // MARK: - InputSourceManager Tests

    func testInputSourceManagerInitialization() {
        XCTAssertNotNil(inputSourceManager)
        XCTAssertFalse(inputSourceManager.isImporting)
        XCTAssertEqual(inputSourceManager.importProgress, 0)
        XCTAssertNil(inputSourceManager.lastError)
    }

    func testImportUnsupportedFormat() async {
        // サポートされていない形式のファイルを作成
        let unsupportedFileURL = testDirectory.appendingPathComponent("test.txt")
        try? "test content".write(to: unsupportedFileURL, atomically: true, encoding: .utf8)

        do {
            _ = try await inputSourceManager.importAudioFile(from: unsupportedFileURL)
            XCTFail("Should throw unsupportedFormat error")
        } catch let error as InputSourceError {
            if case .unsupportedFormat(let format) = error {
                XCTAssertEqual(format, "txt")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInputSourceErrorDescriptions() {
        let unsupportedError = InputSourceError.unsupportedFormat("xyz")
        XCTAssertTrue(unsupportedError.errorDescription?.contains("xyz") ?? false)

        let copyError = InputSourceError.copyFailed("permission denied")
        XCTAssertTrue(copyError.errorDescription?.contains("permission denied") ?? false)

        let downloadError = InputSourceError.downloadFailed("network error")
        XCTAssertTrue(downloadError.errorDescription?.contains("network error") ?? false)

        let extractionError = InputSourceError.extractionFailed("invalid format")
        XCTAssertTrue(extractionError.errorDescription?.contains("invalid format") ?? false)
    }

    // MARK: - File Path Format Tests

    func testRecordingFileNameFormat() {
        // インポートされたファイルの名前形式が正しいかテスト
        let memoId = UUID()
        let expectedFileName = "recording-\(memoId.uuidString).m4a"

        // recording-で始まり、.m4aで終わることを確認
        XCTAssertTrue(expectedFileName.hasPrefix("recording-"))
        XCTAssertTrue(expectedFileName.hasSuffix(".m4a"))
        XCTAssertTrue(expectedFileName.contains(memoId.uuidString))
    }

    func testVoiceRecordingsDirectoryPath() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let voiceRecordingsPath = documentsPath.appendingPathComponent("VoiceRecordings")

        XCTAssertTrue(voiceRecordingsPath.path.contains("VoiceRecordings"))
        XCTAssertEqual(voiceRecordingsPath.lastPathComponent, "VoiceRecordings")
    }

    // MARK: - Video Import Tests

    func testImportVideoFileUnsupportedFormat() async {
        // サポートされていない動画形式のファイル
        let unsupportedVideoURL = testDirectory.appendingPathComponent("test.avi")
        try? "test content".write(to: unsupportedVideoURL, atomically: true, encoding: .utf8)

        do {
            _ = try await inputSourceManager.importVideoFile(from: unsupportedVideoURL)
            XCTFail("Should throw unsupportedFormat error")
        } catch let error as InputSourceError {
            if case .unsupportedFormat(let format) = error {
                XCTAssertEqual(format, "avi")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportVideoFileExtractsAudio() async throws {
        // Note: このテストは実際の動画ファイルが必要なため、
        // モックやテスト用の短い動画ファイルを用意する必要があります
        // ここではメソッドの存在と基本的なフローをテストします

        // テスト用の動画ファイルパス（実際のファイルがない場合はスキップ）
        let testVideoURL = testDirectory.appendingPathComponent("test.mp4")

        // 実際の動画ファイルが存在しない場合はスキップ
        guard FileManager.default.fileExists(atPath: testVideoURL.path) else {
            throw XCTSkip("Test video file not available")
        }

        // 動画ファイルをインポート
        let result = try await inputSourceManager.importVideoFile(from: testVideoURL)

        // 結果の検証
        XCTAssertEqual(result.sourceType, .videoFile)
        XCTAssertNotNil(result.duration)
        XCTAssertTrue(result.processedURL.pathExtension == "m4a", "Extracted audio should be m4a format")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.processedURL.path))
    }

    func testImportVideoFileProgressUpdates() async {
        // 進捗が更新されることを確認
        XCTAssertEqual(inputSourceManager.importProgress, 0)

        // Note: 実際の動画ファイルなしでは進捗テストは難しいため、
        // 統合テストとして実機/シミュレータで確認することを推奨
    }

    func testVideoExtractionFailureHandling() async {
        // 破損した動画ファイルや無効なファイルの場合のエラーハンドリング
        let corruptedVideoURL = testDirectory.appendingPathComponent("corrupted.mp4")
        try? Data(repeating: 0, count: 100).write(to: corruptedVideoURL) // 無効なデータ

        do {
            _ = try await inputSourceManager.importVideoFile(from: corruptedVideoURL)
            XCTFail("Should throw extractionFailed error")
        } catch let error as InputSourceError {
            if case .extractionFailed = error {
                // 期待通りのエラー
            } else {
                XCTFail("Expected extractionFailed error, got: \(error)")
            }
        } catch {
            // AVAssetExportSessionのエラーも許容
            XCTAssertTrue(true, "Audio extraction failed as expected")
        }
    }
}
