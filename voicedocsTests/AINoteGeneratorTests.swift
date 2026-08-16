//
//  AINoteGeneratorTests.swift
//  voicedocsTests
//
//  移植元: VoiceMemo (VoiLog) の VoiLogTests/MeetingMinutesClientTests.swift。
//  voicedocs はクラウドフォールバックを持たないため、
//  「オンデバイス非対応 → クラウドへフォールバック」のケースは
//  「オンデバイス非対応 → modelUnavailable を投げる」に置き換えている。
//  クラウド経路のテスト (MeetingMinutesCloudFallbackTests) は移植対象外。
//

import XCTest
import ComposableArchitecture
@testable import voicedocs

final class AINoteGeneratorTests: XCTestCase {

    // MARK: - 入力バリデーション

    func testGenerate_emptyText_throwsWithoutCallingOnDevice() async {
        let onDeviceCalled = LockIsolated(false)

        do {
            _ = try await AINoteGenerator.generate(
                text: "   ",
                isOnDeviceAvailable: { true },
                onDevice: { _ in
                    onDeviceCalled.setValue(true)
                    return AINoteResult(summary: "", todos: [])
                }
            )
            XCTFail("空文字はエラーになるはず")
        } catch {
            XCTAssertEqual(error as? AINoteError, .noTranscriptionText)
        }

        XCTAssertFalse(onDeviceCalled.value, "空文字ならオンデバイス生成は呼ばれないはず")
    }

    func testGenerate_whitespaceOnlyText_throwsNoTranscriptionText() async {
        do {
            _ = try await AINoteGenerator.generate(
                text: "\n\n  \t ",
                isOnDeviceAvailable: { true },
                onDevice: { _ in AINoteResult(summary: "", todos: []) }
            )
            XCTFail("空白のみはエラーになるはず")
        } catch {
            XCTAssertEqual(error as? AINoteError, .noTranscriptionText)
        }
    }

    // MARK: - オンデバイス経路

    func testGenerate_onDeviceAvailable_usesOnDevice() async throws {
        let expected = AINoteResult(summary: "オンデバイス要約", todos: ["TODO"])

        let result = try await AINoteGenerator.generate(
            text: "会議の文字起こし",
            isOnDeviceAvailable: { true },
            onDevice: { _ in expected }
        )

        XCTAssertEqual(result, expected)
    }

    func testGenerate_passesTextThroughToOnDevice() async throws {
        let received = LockIsolated("")

        _ = try await AINoteGenerator.generate(
            text: "文字起こし本文",
            isOnDeviceAvailable: { true },
            onDevice: { text in
                received.setValue(text)
                return AINoteResult(summary: "", todos: [])
            }
        )

        XCTAssertEqual(received.value, "文字起こし本文")
    }

    // MARK: - 非対応端末（クラウドフォールバックは無い）

    func testGenerate_onDeviceUnavailable_throwsModelUnavailable() async {
        let onDeviceCalled = LockIsolated(false)

        do {
            _ = try await AINoteGenerator.generate(
                text: "会議の文字起こし",
                isOnDeviceAvailable: { false },
                onDevice: { _ in
                    onDeviceCalled.setValue(true)
                    return AINoteResult(summary: "", todos: [])
                }
            )
            XCTFail("非対応端末はエラーになるはず")
        } catch {
            XCTAssertEqual(error as? AINoteError, .modelUnavailable)
        }

        XCTAssertFalse(onDeviceCalled.value, "非対応ならオンデバイス実装は呼ばれないはず")
    }

    // MARK: - 生成失敗の伝播

    func testGenerate_onDeviceThrows_propagatesError() async {
        do {
            _ = try await AINoteGenerator.generate(
                text: "会議の文字起こし",
                isOnDeviceAvailable: { true },
                onDevice: { _ in throw AINoteError.generationFailed("失敗") }
            )
            XCTFail("エラーが伝播するはず")
        } catch {
            XCTAssertEqual(error as? AINoteError, .generationFailed("失敗"))
        }
    }

    // MARK: - 保存フォーマット

    func testFormatForStorage_summaryAndTodos() {
        let result = AINoteResult(summary: "要約本文", todos: ["やること1", "やること2"])

        let text = AINoteGenerator.formatForStorage(result)

        XCTAssertEqual(text, "# 要約\n要約本文\n\n# アクションアイテム\n- やること1\n- やること2")
    }

    func testFormatForStorage_noTodos_omitsActionItemSection() {
        let result = AINoteResult(summary: "要約本文", todos: [])

        let text = AINoteGenerator.formatForStorage(result)

        XCTAssertEqual(text, "# 要約\n要約本文")
        XCTAssertFalse(text.contains("アクションアイテム"))
    }

    // MARK: - エラーメッセージ

    func testErrorDescriptions() {
        XCTAssertEqual(
            AINoteError.modelUnavailable.errorDescription,
            "お使いの端末ではAIノートを利用できません。"
        )
        XCTAssertEqual(
            AINoteError.noTranscriptionText.errorDescription,
            "文字起こしのテキストがありません。先に文字起こしを実行してください。"
        )
        XCTAssertEqual(AINoteError.generationFailed("原因").errorDescription, "原因")
    }
}
