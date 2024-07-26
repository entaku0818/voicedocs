import Foundation
import SwiftUI
import WhisperKit
import AVFoundation
import GoogleMobileAds

struct VoiceMemoDetailView: View {
    private let memo: VoiceMemo
    private let admobKey: String

    @State private var transcription: String = "AI文字起こしを開始するには、以下のボタンを押してください。"
    @State private var isTranscribing = false
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    @State private var interstitial: GADInterstitialAd?

    init(memo: VoiceMemo, admobKey:String) {
        self.memo = memo
        self.admobKey = admobKey
    }

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
                    showInterstitialAd()
                }) {
                    Text(isTranscribing ? "AI文字起こし中..." : "AI文字起こしを開始")
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
        .onAppear {
            loadInterstitialAd()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func loadInterstitialAd() {
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: admobKey, request: request) { ad, error in
            if let error = error {
                print("Failed to load interstitial ad: \(error.localizedDescription)")
                return
            }
            interstitial = ad
        }
    }

    private func showInterstitialAd() {
        if let ad = interstitial {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                print("No root view controller found")

                return
            }
            Task {
                await transcribeAudio()
            }
            ad.present(fromRootViewController: rootViewController)
        } else {
            print("Ad wasn't ready")
            Task {
                await transcribeAudio()
            }
        }
    }


    private func transcribeAudio() async {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            DispatchQueue.main.async {
                transcription = "ドキュメントディレクトリのパスを取得できませんでした。"
            }
            return
        }

        let filePathComponent = (memo.filePath as NSString).lastPathComponent
        let audioURL = documentsDirectory.appendingPathComponent(filePathComponent)

        DispatchQueue.main.async {
            isTranscribing = true
            transcription = "AI文字起こしを取得中..."
        }

        do {
            let whisper = try await WhisperKit()
            let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: DecodingOptions(language: "ja"))

            DispatchQueue.main.async {
                transcription = results.map { $0.text }.joined(separator: "\n")

                isTranscribing = false
            }
        } catch {
            DispatchQueue.main.async {
                transcription = "AI文字起こし中にエラーが発生しました: \(error.localizedDescription)"
                isTranscribing = false
            }
        }
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

            do {
                player = AVPlayer(url: audioURL)
                player?.play()
            } catch {
                print("Failed to load audio file: \(error.localizedDescription)")
            }
        }
        isPlaying.toggle()
    }

    private func stopPlayback() {
        player?.pause()
        isPlaying = false
    }
}

#Preview {
    VoiceMemoDetailView(memo: VoiceMemo(id: UUID(), title: "Sample Memo", text: "This is a sample memo.", date: Date(), filePath: "/path/to/file"), admobKey: "")
}
