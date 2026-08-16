//
//  AINoteFeatureTests.swift
//  voicedocsTests
//
//  移植元: VoiceMemo (VoiLog) の VoiLogTests/MeetingMinutesFeatureTests.swift。
//  プレミアム課金ゲートは voicedocs に無いので削除し、
//  代わりに「Apple Intelligence 非対応端末」の分岐テストを追加している。
//

import XCTest
import ComposableArchitecture
@testable import voicedocs

@MainActor
final class AINoteFeatureTests: XCTestCase {

    private let sampleTranscription = "次回のリリースは来月末を目標にしましょう。テストは来週中には完了させます。"

    private func makeStore(
        transcriptionText: String? = nil,
        savedNoteText: String = "",
        isDeviceSupported: Bool = true,
        isAvailable: @escaping @Sendable () -> Bool = { true },
        generate: @escaping @Sendable (String) async throws -> AINoteResult = { _ in
            AINoteResult(summary: "テスト要約", todos: ["TODO 1", "TODO 2"])
        }
    ) -> TestStore<AINoteFeature.State, AINoteFeature.Action> {
        TestStore(
            initialState: AINoteFeature.State(
                transcriptionText: transcriptionText ?? sampleTranscription,
                savedNoteText: savedNoteText,
                isDeviceSupported: isDeviceSupported
            ),
            reducer: { AINoteFeature() },
            withDependencies: {
                $0.aiNoteClient = AINoteClient(generate: generate, isAvailable: isAvailable)
            }
        )
    }

    // MARK: - onAppear: 端末サポート判定

    func testOnAppear_deviceSupported_keepsSupportedTrue() async {
        let store = makeStore(isDeviceSupported: false, isAvailable: { true })

        await store.send(.view(.onAppear))
        await store.receive(\._availabilityResolved) {
            $0.isDeviceSupported = true
        }
    }

    func testOnAppear_deviceUnsupported_setsSupportedFalse() async {
        let store = makeStore(isAvailable: { false })

        await store.send(.view(.onAppear))
        await store.receive(\._availabilityResolved) {
            $0.isDeviceSupported = false
        }
    }

    // MARK: - 非対応端末ではボタンを押しても何も起きない（クラッシュも無反応な生成も無い）

    func testGenerateTapped_whenDeviceUnsupported_doesNothing() async {
        let generateCalled = LockIsolated(false)
        let store = makeStore(
            isDeviceSupported: false,
            generate: { _ in
                generateCalled.setValue(true)
                return AINoteResult(summary: "", todos: [])
            }
        )

        await store.send(.view(.generateTapped))

        XCTAssertFalse(generateCalled.value, "非対応端末では生成処理を呼ばないはず")
    }

    // MARK: - generateTapped: idle → generating

    func testGenerateTapped_setsStatusToGenerating() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.view(.generateTapped)) {
            $0.status = .generating
        }
        await store.skipReceivedActions()
    }

    // MARK: - 正常フロー: generating → done

    func testGenerateTapped_successFlow_reachesDone() async {
        let expected = AINoteResult(
            summary: "来月末リリースを目標にする。テストは来週完了。",
            todos: ["テストを来週中に完了させる"]
        )
        let store = makeStore(generate: { _ in expected })

        await store.send(.view(.generateTapped)) {
            $0.status = .generating
        }
        await store.receive(\._generationCompleted) {
            $0.status = .done(expected)
        }
    }

    // MARK: - エラーフロー: failed

    func testGenerateTapped_failureFlow_reachesFailed() async {
        let store = makeStore(generate: { _ in throw AINoteError.modelUnavailable })

        await store.send(.view(.generateTapped)) {
            $0.status = .generating
        }
        await store.receive(\._generationFailed) {
            $0.status = .failed(AINoteError.modelUnavailable.errorDescription ?? "")
        }
    }

    func testGenerateTapped_emptyText_reachesFailed() async {
        let store = makeStore(
            transcriptionText: "",
            generate: { _ in throw AINoteError.noTranscriptionText }
        )

        await store.send(.view(.generateTapped)) {
            $0.status = .generating
        }
        await store.receive(\._generationFailed) {
            $0.status = .failed(AINoteError.noTranscriptionText.errorDescription ?? "")
        }
    }

    // MARK: - saveTapped: done → delegate.saved + savedNoteText 更新

    func testSaveTapped_sendsDelegateSavedWithFormattedText() async {
        let result = AINoteResult(summary: "要約テスト", todos: ["TODO A"])
        let expectedText = AINoteGenerator.formatForStorage(result)
        let store = makeStore()

        await store.send(._generationCompleted(result)) {
            $0.status = .done(result)
        }
        await store.send(.view(.saveTapped)) {
            $0.savedNoteText = expectedText
            $0.status = .idle
        }
        await store.receive(\.delegate.saved)
    }

    func testSaveTapped_whenNotDone_doesNothing() async {
        let store = makeStore()
        // status は .idle のまま → saveTapped は無視される
        await store.send(.view(.saveTapped))
    }

    // MARK: - 再生成

    func testGenerateTapped_calledTwice_secondCallOverwrites() async {
        let first = AINoteResult(summary: "1回目", todos: [])
        let second = AINoteResult(summary: "2回目", todos: ["TODO"])
        let callCount = LockIsolated(0)
        let store = makeStore(generate: { _ in
            callCount.withValue { $0 += 1 }
            return callCount.value == 1 ? first : second
        })

        await store.send(.view(.generateTapped)) { $0.status = .generating }
        await store.receive(\._generationCompleted) { $0.status = .done(first) }

        await store.send(.view(.generateTapped)) { $0.status = .generating }
        await store.receive(\._generationCompleted) { $0.status = .done(second) }
    }

    // MARK: - 保存済みノートがある状態から再生成しても、保存済みは保存操作まで維持される

    func testGenerateTapped_withSavedNote_keepsSavedUntilSaveTapped() async {
        let fresh = AINoteResult(summary: "新しい要約", todos: [])
        let store = makeStore(
            savedNoteText: "# 要約\n古いノート",
            generate: { _ in fresh }
        )

        await store.send(.view(.generateTapped)) { $0.status = .generating }
        await store.receive(\._generationCompleted) { $0.status = .done(fresh) }

        XCTAssertEqual(store.state.savedNoteText, "# 要約\n古いノート", "保存操作をするまで保存済みノートは上書きされない")
    }
}
