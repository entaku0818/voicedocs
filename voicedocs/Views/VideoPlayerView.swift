//
//  VideoPlayerView.swift
//  voicedocs
//
//  動画再生用のビュー
//

import SwiftUI
import AVKit

/// 動画再生ビュー
struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(12)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                // ローディング表示
                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(12)

                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
    }

    private func setupPlayer() {
        player = AVPlayer(url: videoURL)
    }
}

/// カスタム動画プレーヤー（コントロール付き）
struct CustomVideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        VStack(spacing: 12) {
            // 動画表示エリア
            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(12)
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }
            }

            // 再生コントロール
            VStack(spacing: 8) {
                // タイムスライダー
                if duration > 0 {
                    HStack(spacing: 8) {
                        Text(formatTime(currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()

                        Slider(value: $currentTime, in: 0...duration) { editing in
                            if !editing {
                                player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                            }
                        }

                        Text(formatTime(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }

                // 再生/停止ボタン
                HStack(spacing: 20) {
                    Button(action: { seekBackward() }) {
                        Image(systemName: "gobackward.10")
                            .font(.title2)
                    }

                    Button(action: { togglePlayPause() }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }

                    Button(action: { seekForward() }) {
                        Image(systemName: "goforward.10")
                            .font(.title2)
                    }
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanup()
        }
    }

    private func setupPlayer() {
        player = AVPlayer(url: videoURL)

        // 動画の長さを取得
        if let duration = player?.currentItem?.asset.duration {
            self.duration = CMTimeGetSeconds(duration)
        }

        // 時間の監視
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)

            // 再生状態を更新
            if let player = player {
                isPlaying = player.rate > 0
            }
        }
    }

    private func togglePlayPause() {
        guard let player = player else { return }

        if player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func seekBackward() {
        guard let player = player else { return }
        let newTime = max(0, currentTime - 10)
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
    }

    private func seekForward() {
        guard let player = player else { return }
        let newTime = min(duration, currentTime + 10)
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
    }

    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func cleanup() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player = nil
    }
}
