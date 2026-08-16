//
//  AINotePersistenceTests.swift
//  voicedocsTests
//
//  AIノートの保存先は既存の Core Data 属性 `aiTranscriptionText`（従来どこからも読まれていなかった空き）。
//  新規属性を足していないのでマイグレーションは不要だが、
//  「AIノートを保存しても既存の文字起こし・タイトル・セグメントが壊れない」ことをここで担保する。
//

import XCTest
@testable import voicedocs

final class AINotePersistenceTests: XCTestCase {
    private var controller: FakeVoiceMemoController!
    private var memoId: UUID!

    override func setUpWithError() throws {
        controller = FakeVoiceMemoController()
        memoId = UUID()
        controller.saveVoiceMemo(
            id: memoId,
            title: "既存メモ",
            text: "既存の文字起こし本文",
            filePath: nil
        )
    }

    override func tearDownWithError() throws {
        controller = nil
        memoId = nil
    }

    // MARK: - 既存データの非破壊

    func testSaveAINote_doesNotOverwriteTranscriptionOrTitle() throws {
        let noteText = AINoteGenerator.formatForStorage(
            AINoteResult(summary: "要約", todos: ["やること"])
        )

        let success = controller.updateVoiceMemo(
            id: memoId,
            title: nil,
            text: nil,
            aiTranscriptionText: noteText
        )

        XCTAssertTrue(success)
        let updated = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))
        XCTAssertEqual(updated.text, "既存の文字起こし本文", "AIノート保存で文字起こし本文が消えてはいけない")
        XCTAssertEqual(updated.title, "既存メモ", "AIノート保存でタイトルが消えてはいけない")
        XCTAssertEqual(updated.aiTranscriptionText, noteText)
    }

    func testSaveAINote_doesNotBreakSegments() throws {
        let before = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))
        let segmentCountBefore = before.segments.count

        _ = controller.updateVoiceMemo(
            id: memoId,
            title: nil,
            text: nil,
            aiTranscriptionText: "# 要約\nテスト"
        )

        let after = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))
        XCTAssertEqual(after.segments.count, segmentCountBefore, "AIノート保存でセグメントが変化してはいけない")
    }

    // MARK: - 既存メモ（aiTranscriptionText が空）でも読み出せる

    func testExistingMemoWithoutAINote_hasEmptyStringNotCrash() throws {
        let memo = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))

        XCTAssertEqual(memo.aiTranscriptionText, "", "既存メモの aiTranscriptionText は空文字で読めるべき")
    }

    func testAINoteState_initializesFromExistingMemo() throws {
        let memo = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))

        let state = AINoteFeature.State(
            transcriptionText: memo.text,
            savedNoteText: memo.aiTranscriptionText
        )

        XCTAssertEqual(state.transcriptionText, "既存の文字起こし本文")
        XCTAssertEqual(state.savedNoteText, "")
        XCTAssertEqual(state.status, .idle)
    }

    // MARK: - 再保存で上書きされる

    func testSaveAINote_twice_overwritesPreviousNote() throws {
        _ = controller.updateVoiceMemo(id: memoId, title: nil, text: nil, aiTranscriptionText: "# 要約\n1回目")
        _ = controller.updateVoiceMemo(id: memoId, title: nil, text: nil, aiTranscriptionText: "# 要約\n2回目")

        let updated = try XCTUnwrap(controller.fetchVoiceMemo(id: memoId))
        XCTAssertEqual(updated.aiTranscriptionText, "# 要約\n2回目")
        XCTAssertEqual(updated.text, "既存の文字起こし本文")
    }
}
