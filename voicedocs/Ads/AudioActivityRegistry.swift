//
//  AudioActivityRegistry.swift
//  voicedocs
//
//  「いま録音中／文字起こし中か」をアプリ全体から1箇所で見られるようにするレジストリ。
//
//  なぜ必要か:
//  voicedocs は `UIBackgroundModes: audio` を持っていて、録音したままアプリを離れられる。
//  そのため**フォアグラウンド復帰時にアプリ起動広告（App Open）を出すと、
//  録音中の画面に全画面広告がかぶる**という最悪の事故が起きる。
//  録音・文字起こしは中核体験なので、広告側から「いま触っていいか」を必ず確認する。
//
//  録音クラスはシングルトンではなく画面ごとに生成されるため
//  （`RealtimeTranscriptionRecorder` / `AudioRecorder` / `SpeechRecognitionManager`）、
//  各インスタンスが自分の状態をここに申告する形にしている。
//

import Foundation

final class AudioActivityRegistry: @unchecked Sendable {
    static let shared = AudioActivityRegistry()

    private let lock = NSLock()
    private var activeOwners = Set<ObjectIdentifier>()

    init() {}

    /// 録音または文字起こしが1つでも動いているか
    var isBusy: Bool {
        lock.withLock { !activeOwners.isEmpty }
    }

    /// 録音/文字起こしの開始・終了を申告する。`didSet` から呼ぶ想定。
    func update(isActive: Bool, for owner: AnyObject) {
        update(isActive: isActive, id: ObjectIdentifier(owner))
    }

    /// deinit から呼ぶ用。`AnyObject` を渡すと解放中のインスタンスを触ることになるため
    /// ObjectIdentifier を直接受ける口を分けてある。
    func update(isActive: Bool, id: ObjectIdentifier) {
        lock.withLock {
            if isActive {
                activeOwners.insert(id)
            } else {
                activeOwners.remove(id)
            }
        }
    }

    /// テスト用
    func reset() {
        lock.withLock { activeOwners.removeAll() }
    }
}
