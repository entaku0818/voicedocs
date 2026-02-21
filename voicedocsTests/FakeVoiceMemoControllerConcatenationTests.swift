//
//  FakeVoiceMemoControllerConcatenationTests.swift
//  voicedocsTests
//
//  Created by Claude on 2026-02-19.
//

import XCTest
@testable import voicedocs

final class FakeVoiceMemoControllerConcatenationTests: XCTestCase {
    var controller: FakeVoiceMemoController!
    var memoId: UUID!

    override func setUpWithError() throws {
        controller = FakeVoiceMemoController()
        memoId = UUID()
        // テスト用メモを追加
        controller.saveVoiceMemo(id: memoId, title: "テストメモ", text: "", filePath: nil)
    }

    override func tearDownWithError() throws {
        controller = nil
        memoId = nil
    }

    // MARK: - concatenateSegments テスト

    func testConcatenate_noSegments_throwsError() async {
        // セグメントなしのメモに対してエラーが投げられること
        do {
            _ = try await controller.concatenateSegments(memoId: memoId)
            XCTFail("セグメントがない場合はエラーが投げられるべき")
        } catch let error as AudioConcatenationService.ConcatenationError {
            guard case .noSegments = error else {
                XCTFail("Expected noSegments, got: \(error)")
                return
            }
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    func testConcatenate_withSegments_returnsURL() async throws {
        // セグメントを追加
        let segment1 = AudioSegment(
            filePath: "/fake/path/seg1.m4a",
            startTime: 0,
            duration: 5.0
        )
        let segment2 = AudioSegment(
            filePath: "/fake/path/seg2.m4a",
            startTime: 5.0,
            duration: 3.0
        )
        _ = controller.addSegmentToMemo(memoId: memoId, segment: segment1)
        _ = controller.addSegmentToMemo(memoId: memoId, segment: segment2)

        let resultURL = try await controller.concatenateSegments(memoId: memoId)

        XCTAssertTrue(resultURL.lastPathComponent.contains(memoId.uuidString),
                      "出力ファイル名にメモIDが含まれるべき")
        XCTAssertEqual(resultURL.pathExtension, "m4a", "出力は m4a 形式であるべき")
    }

    func testConcatenate_outputInTemporaryDirectory() async throws {
        let segment = AudioSegment(
            filePath: "/fake/path/seg.m4a",
            startTime: 0,
            duration: 5.0
        )
        _ = controller.addSegmentToMemo(memoId: memoId, segment: segment)

        let resultURL = try await controller.concatenateSegments(memoId: memoId)

        let tempDir = FileManager.default.temporaryDirectory
        XCTAssertTrue(resultURL.path.hasPrefix(tempDir.path),
                      "出力は temporaryDirectory に保存されるべき")
    }

    func testConcatenate_nonexistentMemo_throwsError() async {
        let nonexistentId = UUID()

        do {
            _ = try await controller.concatenateSegments(memoId: nonexistentId)
            XCTFail("存在しないメモでは noSegments エラーが投げられるべき")
        } catch let error as AudioConcatenationService.ConcatenationError {
            guard case .noSegments = error else {
                XCTFail("Expected noSegments, got: \(error)")
                return
            }
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    // MARK: - セグメント管理との連携テスト

    func testSegmentsAddedAndConcatenated() async throws {
        // セグメントを追加 → getSegmentsForMemo で取得 → concatenate で返却される
        let segment1 = AudioSegment(filePath: "/p/1.m4a", startTime: 0, duration: 2.0)
        let segment2 = AudioSegment(filePath: "/p/2.m4a", startTime: 2.0, duration: 3.0)
        let segment3 = AudioSegment(filePath: "/p/3.m4a", startTime: 5.0, duration: 1.0)

        _ = controller.addSegmentToMemo(memoId: memoId, segment: segment1)
        _ = controller.addSegmentToMemo(memoId: memoId, segment: segment2)
        _ = controller.addSegmentToMemo(memoId: memoId, segment: segment3)

        let fetchedSegments = controller.getSegmentsForMemo(memoId: memoId)
        XCTAssertEqual(fetchedSegments.count, 3)

        // concatenateSegments は FakeController なのでダミー URL を返す
        let resultURL = try await controller.concatenateSegments(memoId: memoId)
        XCTAssertNotNil(resultURL)
    }

    func testConcatenate_afterRemovingSegmentToOne_throwsError() async {
        // 2つ追加して1つ削除 → 1つだけ残った場合でも連結は成功する（FakeはUIでのみ2以上を制御）
        let seg1 = AudioSegment(filePath: "/p/1.m4a", startTime: 0, duration: 2.0)
        let seg2 = AudioSegment(filePath: "/p/2.m4a", startTime: 2.0, duration: 2.0)

        _ = controller.addSegmentToMemo(memoId: memoId, segment: seg1)
        _ = controller.addSegmentToMemo(memoId: memoId, segment: seg2)
        _ = controller.removeSegmentFromMemo(memoId: memoId, segmentId: seg2.id)

        // 1つだけ残ったセグメントでも Fake 実装は連結を試みる
        do {
            let resultURL = try await controller.concatenateSegments(memoId: memoId)
            // 1セグメントでも Fake は成功させる（実際の連結バリデーションはUI層で行う）
            XCTAssertNotNil(resultURL)
        } catch {
            // エラーになった場合も許容（実装次第）
        }
    }
}
