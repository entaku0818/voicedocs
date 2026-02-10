//
//  URLAudioInputView.swift
//  voicedocs
//
//  Created by Claude on 2025/02/10.
//

import Foundation
import SwiftUI

/// URLから音声を取得するための入力ビュー
struct URLAudioInputView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = URLAudioInputViewModel()
    let onImportComplete: (ImportResult) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // ヘッダー説明
                VStack(alignment: .leading, spacing: 8) {
                    Text("音声ファイルのURLを入力")
                        .font(.headline)

                    Text("MP3、M4A、WAV等の音声ファイルのURLを入力してください。ポッドキャストのエピソードURLにも対応しています。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // URL入力フィールド
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                        TextField("https://example.com/audio.mp3", text: $viewModel.urlString)
                            .textFieldStyle(.plain)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .disabled(viewModel.isDownloading)

                        if !viewModel.urlString.isEmpty {
                            Button(action: { viewModel.urlString = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .disabled(viewModel.isDownloading)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    // バリデーションメッセージ
                    if let validationMessage = viewModel.validationMessage {
                        HStack {
                            Image(systemName: viewModel.isValidURL ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(viewModel.isValidURL ? .green : .red)
                            Text(validationMessage)
                                .font(.caption)
                                .foregroundColor(viewModel.isValidURL ? .green : .red)
                        }
                    }
                }
                .padding(.horizontal)

                // 対応形式
                VStack(alignment: .leading, spacing: 4) {
                    Text("対応形式")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text("MP3, M4A, WAV, AAC, AIFF")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Spacer()

                // ダウンロード進捗
                if viewModel.isDownloading {
                    VStack(spacing: 12) {
                        ProgressView(value: viewModel.downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())

                        HStack {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(.blue)
                            Text(viewModel.progressMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // エラーメッセージ
                if let errorMessage = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // 著作権に関する注意
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("著作権に関する注意")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Text("著作権で保護されたコンテンツをダウンロードする場合は、適切な許可を得ていることを確認してください。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)

                // ダウンロードボタン
                Button(action: {
                    Task {
                        if let result = await viewModel.downloadAudio() {
                            onImportComplete(result)
                            isPresented = false
                        }
                    }
                }) {
                    HStack {
                        if viewModel.isDownloading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(viewModel.isDownloading ? "ダウンロード中..." : "ダウンロード")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canDownload ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!viewModel.canDownload)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("URLから取得")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        viewModel.cancelDownload()
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class URLAudioInputViewModel: ObservableObject {
    @Published var urlString: String = "" {
        didSet {
            validateURL()
        }
    }
    @Published var isValidURL: Bool = false
    @Published var validationMessage: String?
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var progressMessage: String = ""
    @Published var errorMessage: String?

    private let inputSourceManager = InputSourceManager()

    var canDownload: Bool {
        isValidURL && !isDownloading
    }

    func validateURL() {
        errorMessage = nil

        if urlString.isEmpty {
            isValidURL = false
            validationMessage = nil
            return
        }

        // URL形式チェック
        guard let url = URL(string: urlString) else {
            isValidURL = false
            validationMessage = "無効なURL形式です"
            return
        }

        // スキームチェック
        guard url.scheme == "http" || url.scheme == "https" else {
            isValidURL = false
            validationMessage = "httpまたはhttpsのURLを入力してください"
            return
        }

        // ホストチェック
        guard url.host != nil else {
            isValidURL = false
            validationMessage = "有効なホスト名を入力してください"
            return
        }

        // 拡張子チェック（オプション：警告として表示）
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty && !SupportedAudioFormats.extensions.contains(pathExtension) {
            isValidURL = true
            validationMessage = "音声形式でない可能性があります（ダウンロード後に確認します）"
            return
        }

        isValidURL = true
        if SupportedAudioFormats.extensions.contains(pathExtension) {
            validationMessage = "有効な音声ファイルURLです"
        } else {
            validationMessage = "URLは有効です"
        }
    }

    func downloadAudio() async -> ImportResult? {
        isDownloading = true
        downloadProgress = 0
        progressMessage = "ダウンロードを開始しています..."
        errorMessage = nil

        do {
            let result = try await inputSourceManager.downloadAudioFromURL(urlString) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                    if progress < 0.9 {
                        self?.progressMessage = "ダウンロード中... \(Int(progress * 100))%"
                    } else {
                        self?.progressMessage = "音声ファイルを検証中..."
                    }
                }
            }

            isDownloading = false
            return result

        } catch {
            isDownloading = false
            if let inputError = error as? InputSourceError {
                errorMessage = inputError.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    func cancelDownload() {
        isDownloading = false
        downloadProgress = 0
    }
}

#Preview {
    URLAudioInputView(isPresented: .constant(true)) { _ in }
}
