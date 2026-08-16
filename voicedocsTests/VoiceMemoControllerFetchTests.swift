//
//  VoiceMemoControllerFetchTests.swift
//  voicedocsTests
//
//  本物の VoiceMemoController（Core Data → VoiceMemo 変換）に対する回帰テスト。
//  FakeVoiceMemoController は変換経路を通らないため、issue #32
//  （fetchVoiceMemo(id:) が aiTranscriptionText / videoFilePath を復元しない）を
//  検出できなかった。ここでは inMemory ストアで本物の実装を直接叩く。
//

import XCTest
import CoreData
@testable import voicedocs

final class VoiceMemoControllerFetchTests: XCTestCase {
    private var controller: VoiceMemoController!
    private var memoId: UUID!

    override func setUpWithError() throws {
        controller = VoiceMemoController(inMemory: true)
        memoId = UUID()
        controller.saveVoiceMemo(
            id: memoId,
            title: "既存メモ",
            text: "既存の文字起こし本文",
            filePath: nil,
            videoFilePath: "/tmp/dummy-video.mov"
        )
    }

    override func tearDownWithError() throws {
        controller = nil
        memoId = nil
    }

    // MARK: - issue #32 の回帰

    func testFetchVoiceMemoById_restoresAITranscriptionText() throws {
        let noteText = "# 要約\n保存済みのAIノート"
        XCTAssertTrue(
            controller.updateVoiceMemo(id: memoId, title: nil, text: nil, aiTranscriptionText: noteText)
        )

        let memo = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))
        XCTAssertEqual(
            memo.aiTranscriptionText,
            noteText,
            "単体取得でAIノートが復元されないと、詳細画面で保存済みノートが消えて見える（issue #32）"
        )
    }

    func testFetchVoiceMemoById_restoresVideoFilePath() throws {
        let memo = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))

        XCTAssertEqual(memo.videoFilePath, "/tmp/dummy-video.mov")
    }

    // MARK: - 一覧取得と単体取得の整合

    func testFetchVoiceMemoById_matchesListFetchResult() throws {
        _ = controller.updateVoiceMemo(id: memoId, title: nil, text: nil, aiTranscriptionText: "# 要約\n整合性チェック")

        let fromList = try XCTUnwrap(controller.fetchVoiceMemos().first { $0.id == memoId })
        let fromSingle = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))

        XCTAssertEqual(fromSingle.title, fromList.title)
        XCTAssertEqual(fromSingle.text, fromList.text)
        XCTAssertEqual(fromSingle.aiTranscriptionText, fromList.aiTranscriptionText)
        XCTAssertEqual(fromSingle.videoFilePath, fromList.videoFilePath)
        XCTAssertEqual(fromSingle.segments.count, fromList.segments.count)
    }

    // MARK: - AIノート未生成のメモ

    func testFetchVoiceMemoById_withoutAINote_returnsEmptyString() throws {
        let memo = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))

        XCTAssertEqual(memo.aiTranscriptionText, "")
    }
}
