import SwiftUI

struct RealtimeTranscriptionResultView: View {
    @ObservedObject var recorder: RealtimeTranscriptionRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("リアルタイム文字起こし")
                    .font(.headline)
                Spacer()
                if recorder.isTranscribing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("認識中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if recorder.transcribedText.isEmpty {
                        if recorder.isRecording {
                            Text("話しかけてください...")
                                .foregroundColor(.blue)
                        } else {
                            Text("録音を開始してください")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(recorder.transcribedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(minHeight: 100, maxHeight: 200)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}
