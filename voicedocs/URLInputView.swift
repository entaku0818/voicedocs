//
//  URLInputView.swift
//  voicedocs
//

import SwiftUI
import UIKit

/// URL入力ビュー
struct URLInputView: View {
    @Binding var isPresented: Bool
    let onURLSubmitted: (String) -> Void

    @State private var urlText = ""

    private var isValidURL: Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("音声ファイルのURLを入力してください")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("https://example.com/audio.mp3", text: $urlText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if !urlText.isEmpty && !isValidURL {
                        Text("URLはhttp://またはhttps://で始まる必要があります")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Spacer()

                Button(action: {
                    let trimmed = urlText.trimmingCharacters(in: .whitespaces)
                    isPresented = false
                    onURLSubmitted(trimmed)
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("ダウンロード")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidURL ? Color.orange : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!isValidURL)
            }
            .padding()
            .navigationTitle("URLから取得")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
