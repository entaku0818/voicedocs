//
//  VoiceMemoDetailView.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation
import SwiftUI
import WhisperKit
import AVFoundation

struct VoiceMemoDetailView: View {
    var memo: VoiceMemo
    @State private var transcription: String = "トランスクリプションを開始するには、以下のボタンを押してください。"
    @State private var isTranscribing = false
    @State private var isPlaying = false
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading) {
            Text(memo.text)

            Text(transcription)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button(action: {
                    Task {
                        await transcribeAudio()
                    }
                }) {
                    Text(isTranscribing ? "トランスクリプション中..." : "トランスクリプションを開始")
                        .padding()
                        .background(isTranscribing ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(isTranscribing)

                Button(action: {
                    togglePlayback()
                }) {
                    Text(isPlaying ? "停止" : "再生")
                        .padding()
                        .background(isPlaying ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

            }

            Spacer()
        }
        .navigationTitle(memo.title)
        .padding(.horizontal, 20)
        .onDisappear {
            stopPlayback()
        }
    }

    private func transcribeAudio() async {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            transcription = "ドキュメントディレクトリのパスを取得できませんでした。"
            return
        }

        let filePathComponent = (memo.filePath as NSString).lastPathComponent
        let audioURL = documentsDirectory.appendingPathComponent(filePathComponent)

        isTranscribing = true
        transcription = "トランスクリプションを取得中..."

        do {
            let whisper = try? await WhisperKit(model: "large-v3")
            if let result = try await whisper?.transcribe(audioPath: audioURL.path, decodeOptions: DecodingOptions(language: "ja"))?.text {
                transcription = result
            } else {
                transcription = "トランスクリプションを取得できませんでした。"
            }
        } catch {
            transcription = "トランスクリプション中にエラーが発生しました: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let filePathComponent = (memo.filePath as NSString).lastPathComponent
            let audioURL = documentsDirectory.appendingPathComponent(filePathComponent)

            player = AVPlayer(url: audioURL)
            player?.play()
        }
        isPlaying.toggle()
    }

    private func stopPlayback() {
        player?.pause()
        isPlaying = false
    }
}

#Preview {
    VoiceMemoDetailView(memo: VoiceMemo(id: UUID(), title: "Sample Memo", text: "This is a sample memo.", date: Date(), filePath: "/path/to/file"))
}
