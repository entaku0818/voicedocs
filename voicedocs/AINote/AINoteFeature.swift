//
//  AINoteFeature.swift
//  voicedocs
//
//  文字起こし結果から「要約 + アクションアイテム」をオンデバイス生成するAIノート機能。
//
//  移植元: VoiceMemo (VoiLog) の Transcription/MeetingMinutesFeature.swift。
//  ただし voicedocs では FoundationModels のオンデバイス経路のみを採用し、
//  クラウド (Gemini /minutes) フォールバックは持たない。理由:
//    - voicedocs は最低 iOS 26.0 なので FoundationModels が常に前提にできる
//    - サーバ経由にすると Firebase Auth の導入とプロジェクト跨ぎのトークン検証が必要になる
//      （voicedocs は Firebase プロジェクト voicedocs-3109d、サーバ側は voilog）
//  オンデバイスが使えない端末では生成せず、UIで「利用できません」を出す。
//

import ComposableArchitecture
import Foundation
import FoundationModels

// MARK: - Result

struct AINoteResult: Equatable, Sendable {
    var summary: String
    var todos: [String]
}

// MARK: - Error

enum AINoteError: Error, LocalizedError, Equatable {
    case noTranscriptionText
    case modelUnavailable
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTranscriptionText:
            return "文字起こしのテキストがありません。先に文字起こしを実行してください。"
        case .modelUnavailable:
            return "お使いの端末ではAIノートを利用できません。"
        case .generationFailed(let message):
            return message
        }
    }
}

// MARK: - Client

struct AINoteClient: Sendable {
    /// 文字起こしテキストからAIノートを生成する
    var generate: @Sendable (String) async throws -> AINoteResult
    /// この端末でオンデバイス生成が使えるか
    var isAvailable: @Sendable () -> Bool
}

extension AINoteClient: DependencyKey {
    static let liveValue = AINoteClient(
        generate: { text in
            try await AINoteGenerator.generate(
                text: text,
                isOnDeviceAvailable: { SystemLanguageModel.default.isAvailable },
                onDevice: { try await generateWithFoundationModels($0) }
            )
        },
        isAvailable: { SystemLanguageModel.default.isAvailable }
    )

    static let testValue = AINoteClient(
        generate: { _ in
            AINoteResult(summary: "テスト要約です。", todos: ["TODO 1", "TODO 2"])
        },
        isAvailable: { true }
    )
}

extension DependencyValues {
    var aiNoteClient: AINoteClient {
        get { self[AINoteClient.self] }
        set { self[AINoteClient.self] = newValue }
    }
}

// MARK: - Generator

/// オンデバイスが使えるかどうかで処理を振り分ける純粋なロジック。
///
/// 実際の `SystemLanguageModel` 参照は呼び出し元からクロージャとして注入するため、
/// このロジック自体は実機の Apple Intelligence 状態に依存せずテストできる。
enum AINoteGenerator {
    static func generate(
        text: String,
        isOnDeviceAvailable: () -> Bool,
        onDevice: (String) async throws -> AINoteResult
    ) async throws -> AINoteResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AINoteError.noTranscriptionText
        }
        guard isOnDeviceAvailable() else {
            throw AINoteError.modelUnavailable
        }
        return try await onDevice(text)
    }

    /// 保存用テキスト（Core Data の aiTranscriptionText に入れる形式）
    static func formatForStorage(_ result: AINoteResult) -> String {
        var lines = ["# 要約", result.summary]
        if !result.todos.isEmpty {
            lines += ["", "# アクションアイテム"]
            lines += result.todos.map { "- \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - FoundationModels (on-device)

@Generable
private struct GeneratedAINote {
    @Guide(description: "文字起こし内容の要約（日本語、3〜5文で簡潔に）")
    var summary: String
    @Guide(description: "文字起こしから抽出したアクションアイテムやTODOのリスト（日本語）")
    var todos: [String]
}

private func generateWithFoundationModels(_ text: String) async throws -> AINoteResult {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
        throw AINoteError.modelUnavailable
    }
    let session = LanguageModelSession(model: model)
    let prompt = """
    以下の文字起こしから、要約とアクションアイテムを日本語で作成してください。

    文字起こし:
    \(text)
    """
    do {
        let response = try await session.respond(to: prompt, generating: GeneratedAINote.self)
        let note = response.content
        return AINoteResult(summary: note.summary, todos: note.todos)
    } catch {
        throw AINoteError.generationFailed(error.localizedDescription)
    }
}

// MARK: - Reducer

@Reducer
struct AINoteFeature {
    @ObservableState
    struct State: Equatable {
        /// 生成元になる文字起こしテキスト（親から同期される）
        var transcriptionText: String = ""
        /// 保存済みAINoteの本文（Core Data の aiTranscriptionText 由来）
        var savedNoteText: String = ""
        var status: Status = .idle
        /// この端末でオンデバイス生成が使えるか。onAppear で確定させる
        var isDeviceSupported = true

        enum Status: Equatable {
            case idle
            case generating
            case done(AINoteResult)
            case failed(String)
        }
    }

    @CasePathable
    enum Action: ViewAction {
        case view(View)
        case delegate(Delegate)
        case _availabilityResolved(Bool)
        case _generationCompleted(AINoteResult)
        case _generationFailed(String)

        @CasePathable
        enum View {
            case onAppear
            case generateTapped
            case saveTapped
        }

        @CasePathable
        enum Delegate {
            case saved(String)
        }
    }

    @Dependency(\.aiNoteClient) var aiNoteClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                return .run { send in
                    await send(._availabilityResolved(aiNoteClient.isAvailable()))
                }

            case .view(.generateTapped):
                guard state.isDeviceSupported else { return .none }
                state.status = .generating
                let text = state.transcriptionText
                return .run { send in
                    do {
                        let result = try await aiNoteClient.generate(text)
                        await send(._generationCompleted(result))
                    } catch {
                        let message = (error as? AINoteError)?.errorDescription
                            ?? error.localizedDescription
                        await send(._generationFailed(message))
                    }
                }

            case .view(.saveTapped):
                guard case let .done(result) = state.status else { return .none }
                let combined = AINoteGenerator.formatForStorage(result)
                state.savedNoteText = combined
                state.status = .idle
                return .send(.delegate(.saved(combined)))

            case let ._availabilityResolved(isAvailable):
                state.isDeviceSupported = isAvailable
                return .none

            case let ._generationCompleted(result):
                state.status = .done(result)
                return .none

            case let ._generationFailed(message):
                state.status = .failed(message)
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
