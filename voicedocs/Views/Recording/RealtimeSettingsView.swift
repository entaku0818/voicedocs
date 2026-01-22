import SwiftUI

struct RealtimeSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("録音設定") {
                    HStack {
                        Image(systemName: "waveform.circle")
                        Text("録音品質")
                        Spacer()
                        Text("高品質")
                            .foregroundColor(.secondary)
                    }
                }

                Section("音声認識設定") {
                    HStack {
                        Image(systemName: "mic.circle")
                        Text("認識言語")
                        Spacer()
                        Text("日本語")
                            .foregroundColor(.secondary)
                    }
                }

                Section("アプリ情報") {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}
