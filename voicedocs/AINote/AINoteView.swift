//
//  AINoteView.swift
//  voicedocs
//
//  移植元: VoiceMemo (VoiLog) の Transcription/MeetingMinutesView.swift。
//  voicedocs では詳細画面のインラインセクションとして表示するため、
//  タブ全画面前提のレイアウトとプレミアム課金ゲートは持たない。
//  代わりに「この端末では使えない」分岐を持つ（Apple Intelligence 非対応端末向け）。
//

import ComposableArchitecture
import SwiftUI

@ViewAction(for: AINoteFeature.self)
struct AINoteView: View {
    @Bindable var store: StoreOf<AINoteFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !store.isDeviceSupported {
                unsupportedView
            } else {
                switch store.status {
                case .idle:
                    idleView
                case .generating:
                    generatingView
                case let .done(result):
                    resultView(result)
                case let .failed(message):
                    failedView(message: message)
                }
            }
        }
        .onAppear {
            send(.onAppear)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
            Text("AIノート")
                .font(.headline)
        }
    }

    // MARK: - 非対応端末

    private var unsupportedView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("お使いの端末ではAIノートを利用できません")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("AIノートは Apple Intelligence に対応した端末で利用できます。設定でApple Intelligenceが有効か確認してください。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.savedNoteText.isEmpty {
                Text("文字起こし結果から、要約とアクションアイテムを自動生成します。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                savedPreview
            }

            Button(store.savedNoteText.isEmpty ? "AIノートを生成" : "AIノートを再生成") {
                send(.generateTapped)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(store.transcriptionText.isEmpty)

            if store.transcriptionText.isEmpty {
                Text("先に文字起こしを実行してください。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var savedPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("保存済みのAIノート")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(store.savedNoteText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.purple.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Generating

    private var generatingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                Text("AIノートを生成中...")
                    .font(.subheadline)
            }
            Text("オンデバイスで処理しています。しばらくお待ちください。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - Result

    private func resultView(_ result: AINoteResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summarySection(result.summary)

            if !result.todos.isEmpty {
                todoSection(result.todos)
            }

            Button("保存") {
                send(.saveTapped)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding()
        .background(Color.purple.opacity(0.06))
        .cornerRadius(8)
    }

    private func summarySection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("要約")
                .font(.subheadline.bold())
                .foregroundColor(.purple)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func todoSection(_ todos: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("アクションアイテム")
                .font(.subheadline.bold())
                .foregroundColor(.purple)
            ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundColor(.purple)
                        .padding(.top, 3)
                    Text(todo)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("AIノートの生成に失敗しました")
                    .font(.subheadline.bold())
            }
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            Button("再試行") {
                send(.generateTapped)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}
