//
//  VoiceMemoDetailView.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation
import SwiftUI
import WhisperKit

struct VoiceMemoDetailView: View {
    var memo: VoiceMemo
    @State private var transcription: String = "トランスクリプションを開始するには、以下のボタンを押してください。"
    @State private var isTranscribing = false

    var body: some View {
        VStack(alignment: .leading) {
            Text(memo.title)
                .font(.largeTitle)
                .padding()

            Text(memo.text)
                .padding()

            Text(transcription)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding()

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
            .padding()

            Spacer()
        }
        .navigationTitle("Memo Details")
        .padding()
    }

    private func transcribeAudio() async {
        guard let audioURL = URL(string: memo.filePath) else {
            transcription = "音声ファイルのパスが無効です。"
            return
        }

        isTranscribing = true
        transcription = "トランスクリプションを取得中..."

        do {
            let whisper = try await WhisperKit()
            if let result = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: DecodingOptions(language: "ja"))?.text {
                transcription = result
            } else {
                transcription = "トランスクリプションを取得できませんでした。"
            }
        } catch {
            transcription = "トランスクリプション中にエラーが発生しました: \(error.localizedDescription)"
        }

        isTranscribing = false
    }
}

#Preview {
    VoiceMemoDetailView(memo: VoiceMemo(id: UUID(), title: "Sample Memo", text: "This is a sample memo.", date: Date(), filePath: "/path/to/file"))
}
