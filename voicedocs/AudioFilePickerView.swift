//
//  AudioFilePickerView.swift
//  voicedocs
//
//  Created by Claude on 2025/01/17.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 音声ファイルピッカー
struct AudioFilePickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onFilePicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 対応する音声形式
        let supportedTypes: [UTType] = [
            .audio,
            .mpeg4Audio,
            .mp3,
            .wav,
            .aiff
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioFilePickerView

        init(_ parent: AudioFilePickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            if let url = urls.first {
                parent.onFilePicked(url)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

/// インポート結果表示シート
struct ImportResultSheet: View {
    let result: ImportResult
    let onTranscribe: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // ファイル情報
                VStack(spacing: 16) {
                    Image(systemName: result.sourceType.iconName)
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text(result.fileName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 20) {
                        Label(result.fileSizeString, systemImage: "doc.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let duration = result.durationString {
                            Label(duration, systemImage: "clock")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Spacer()

                // アクションボタン
                VStack(spacing: 12) {
                    Button(action: onTranscribe) {
                        HStack {
                            Image(systemName: "waveform")
                            Text("文字起こしを開始")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button(action: onCancel) {
                        Text("キャンセル")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .navigationTitle("ファイルをインポート")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// インポート進捗表示
struct ImportProgressView: View {
    let progress: Double
    let fileName: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())

            Text("インポート中...")
                .font(.headline)

            Text(fileName)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}
