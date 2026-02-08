//
//  PhotoVideoPickerView.swift
//  voicedocs
//
//  写真ライブラリから動画を選択するためのピッカー
//

import SwiftUI
import PhotosUI

/// 写真ライブラリから動画を選択するピッカー
struct PhotoVideoPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onVideoPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())

        // 動画のみを選択可能にする
        configuration.filter = .videos

        // 単一選択のみ
        configuration.selectionLimit = 1

        // プレビューを表示
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoVideoPickerView

        init(_ parent: PhotoVideoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false

            guard let result = results.first else { return }

            // 動画ファイルを取得
            if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let url = url, error == nil else {
                        AppLogger.fileOperation.error("Failed to load video: \(error?.localizedDescription ?? "Unknown error")")
                        return
                    }

                    // 一時ファイルにコピー（元のURLは一時的なもので消えてしまうため）
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)

                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)

                        DispatchQueue.main.async {
                            self.parent.onVideoPicked(tempURL)
                        }
                    } catch {
                        AppLogger.fileOperation.error("Failed to copy video file: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
