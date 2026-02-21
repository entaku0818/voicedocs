//
//  AudioConcatenationServiceTests.swift
//  voicedocsTests
//
//  Created by Claude on 2026-02-19.
//

import XCTest
import AVFoundation
@testable import voicedocs

@MainActor
final class AudioConcatenationServiceTests: XCTestCase {
    var service: AudioConcatenationService!
    var testDirectory: URL!

    override func setUpWithError() throws {
        service = AudioConcatenationService()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioConcatenationServiceTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        service = nil
        if let dir = testDirectory, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        testDirectory = nil
    }

    // MARK: - 初期状態テスト

    func testInitialState() {
        XCTAssertEqual(service.progress, 0.0, accuracy: 0.001)
        XCTAssertFalse(service.isProcessing)
    }

    // MARK: - ConcatenationError errorDescription テスト

    func testErrorDescription_noSegments() {
        let error = AudioConcatenationService.ConcatenationError.noSegments
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("セグメント") ?? false)
    }

    func testErrorDescription_fileNotFound() {
        let path = "/test/missing.m4a"
        let error = AudioConcatenationService.ConcatenationError.fileNotFound(path)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains(path) ?? false)
    }

    func testErrorDescription_compositionFailed() {
        let message = "トラック作成失敗"
        let error = AudioConcatenationService.ConcatenationError.compositionFailed(message)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false)
    }

    func testErrorDescription_exportFailed() {
        let message = "エクスポート失敗"
        let error = AudioConcatenationService.ConcatenationError.exportFailed(message)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false)
    }

    func testErrorDescription_unknown() {
        let message = "謎のエラー"
        let error = AudioConcatenationService.ConcatenationError.unknown(message)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false)
    }

    // MARK: - concatenateSegments エラーケーステスト

    func testConcatenate_emptySegments_throwsNoSegmentsError() async {
        do {
            _ = try await service.concatenateSegments([])
            XCTFail("空配列では noSegments エラーが投げられるべき")
        } catch let error as AudioConcatenationService.ConcatenationError {
            guard case .noSegments = error else {
                XCTFail("Expected noSegments, got: \(error)")
                return
            }
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    func testConcatenate_nonexistentFile_throwsFileNotFoundError() async {
        let nonexistentPath = "/nonexistent/audio_\(UUID().uuidString).m4a"
        let segment = AudioSegment(
            filePath: nonexistentPath,
            startTime: 0,
            duration: 5.0
        )

        do {
            _ = try await service.concatenateSegments([segment])
            XCTFail("存在しないファイルでは fileNotFound エラーが投げられるべき")
        } catch let error as AudioConcatenationService.ConcatenationError {
            guard case .fileNotFound(let path) = error else {
                XCTFail("Expected fileNotFound, got: \(error)")
                return
            }
            XCTAssertEqual(path, nonexistentPath)
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    func testConcatenate_secondSegmentMissing_throwsFileNotFoundError() async throws {
        // 1つ目のファイルは作成するが、2つ目は存在しない
        let firstURL = testDirectory.appendingPathComponent("seg1.m4a")
        try createSilentAudioFile(at: firstURL, durationSeconds: 1.0)

        let missingPath = testDirectory.appendingPathComponent("seg2_missing.m4a").path

        let segments = [
            AudioSegment(filePath: firstURL.path, startTime: 0, duration: 1.0),
            AudioSegment(filePath: missingPath, startTime: 1.0, duration: 1.0)
        ]

        do {
            _ = try await service.concatenateSegments(segments)
            XCTFail("存在しないファイルでは fileNotFound エラーが投げられるべき")
        } catch let error as AudioConcatenationService.ConcatenationError {
            guard case .fileNotFound = error else {
                XCTFail("Expected fileNotFound, got: \(error)")
                return
            }
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    // MARK: - resetProgress テスト

    func testResetProgress() {
        // progress を手動で変更はできないが、resetProgress() 呼び出し後は 0.0 になる
        service.resetProgress()
        XCTAssertEqual(service.progress, 0.0, accuracy: 0.001)
    }

    // MARK: - 連結成功テスト

    func testConcatenate_twoSegments_returnsURL() async throws {
        let url1 = testDirectory.appendingPathComponent("seg1.m4a")
        let url2 = testDirectory.appendingPathComponent("seg2.m4a")
        try createSilentAudioFile(at: url1, durationSeconds: 1.0)
        try createSilentAudioFile(at: url2, durationSeconds: 1.0)

        let segments = [
            AudioSegment(filePath: url1.path, startTime: 0, duration: 1.0),
            AudioSegment(filePath: url2.path, startTime: 1.0, duration: 1.0)
        ]

        let outputURL = try await service.concatenateSegments(segments)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "連結ファイルが作成されるべき")
        XCTAssertEqual(outputURL.pathExtension, "m4a", "出力ファイルは m4a 形式であるべき")

        // クリーンアップ
        try? FileManager.default.removeItem(at: outputURL)
    }

    func testConcatenate_customOutputFileName() async throws {
        let url1 = testDirectory.appendingPathComponent("seg1.m4a")
        let url2 = testDirectory.appendingPathComponent("seg2.m4a")
        try createSilentAudioFile(at: url1, durationSeconds: 1.0)
        try createSilentAudioFile(at: url2, durationSeconds: 1.0)

        let segments = [
            AudioSegment(filePath: url1.path, startTime: 0, duration: 1.0),
            AudioSegment(filePath: url2.path, startTime: 1.0, duration: 1.0)
        ]

        let customName = "test_output.m4a"
        let outputURL = try await service.concatenateSegments(segments, outputFileName: customName)

        XCTAssertEqual(outputURL.lastPathComponent, customName, "指定したファイル名で出力されるべき")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        // クリーンアップ
        try? FileManager.default.removeItem(at: outputURL)
    }

    func testConcatenate_progressReachesOne() async throws {
        let url1 = testDirectory.appendingPathComponent("seg1.m4a")
        let url2 = testDirectory.appendingPathComponent("seg2.m4a")
        try createSilentAudioFile(at: url1, durationSeconds: 1.0)
        try createSilentAudioFile(at: url2, durationSeconds: 1.0)

        let segments = [
            AudioSegment(filePath: url1.path, startTime: 0, duration: 1.0),
            AudioSegment(filePath: url2.path, startTime: 1.0, duration: 1.0)
        ]

        let outputURL = try await service.concatenateSegments(segments)

        XCTAssertEqual(service.progress, 1.0, accuracy: 0.001, "完了後 progress は 1.0 になるべき")
        XCTAssertFalse(service.isProcessing, "完了後 isProcessing は false になるべき")

        // クリーンアップ
        try? FileManager.default.removeItem(at: outputURL)
    }

    func testConcatenate_threeSegments_returnsURL() async throws {
        let url1 = testDirectory.appendingPathComponent("seg1.m4a")
        let url2 = testDirectory.appendingPathComponent("seg2.m4a")
        let url3 = testDirectory.appendingPathComponent("seg3.m4a")
        try createSilentAudioFile(at: url1, durationSeconds: 1.0)
        try createSilentAudioFile(at: url2, durationSeconds: 1.0)
        try createSilentAudioFile(at: url3, durationSeconds: 1.0)

        let segments = [
            AudioSegment(filePath: url1.path, startTime: 0, duration: 1.0),
            AudioSegment(filePath: url2.path, startTime: 1.0, duration: 1.0),
            AudioSegment(filePath: url3.path, startTime: 2.0, duration: 1.0)
        ]

        let outputURL = try await service.concatenateSegments(segments)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        // クリーンアップ
        try? FileManager.default.removeItem(at: outputURL)
    }

    // MARK: - ヘルパー: 無音の m4a ファイル作成

    private func createSilentAudioFile(at url: URL, durationSeconds: TimeInterval) throws {
        let sampleRate: Double = 44100.0
        let channelCount = 1
        let totalSamples = AVAudioFrameCount(sampleRate * durationSeconds)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else {
            throw NSError(domain: "TestHelper", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioFormat 作成失敗"])
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalSamples) else {
            throw NSError(domain: "TestHelper", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioPCMBuffer 作成失敗"])
        }
        buffer.frameLength = totalSamples

        // 無音（ゼロ埋め）
        if let channelData = buffer.floatChannelData {
            for ch in 0..<channelCount {
                memset(channelData[ch], 0, Int(totalSamples) * MemoryLayout<Float>.size)
            }
        }

        // m4a (AAC) として書き出す
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]

        let audioFile = try AVAudioFile(forWriting: url, settings: outputSettings)
        try audioFile.write(from: buffer)
    }
}
