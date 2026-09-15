//
//  AdLoadWaiter.swift
//  voicedocs
//
//  「コールバック形式の広告ロードを、上限つきで待つ」だけの小さな部品。
//
//  App Open 広告の取得には通常1〜2秒かかる。未ロードなら即諦める実装だと
//  起動時にほぼ間に合わず、他プロダクトでは表示率が 0.2%（575リクエスト→1表示）まで落ちた。
//  かといって無制限に待つとアプリが無反応に見えるので、上限つきで待つ必要がある。
//
//  タイムアウトしてもロード自体はキャンセルしない。遅れて届いた広告は
//  呼び出し側が保持して次の機会に使えるようにする（リクエストの無駄打ちを避けるため）。
//

import Foundation

enum AdLoadWaiter {
    /// `start` に渡した `done` が呼ばれるか、`timeout` 秒経つまで待つ。
    ///
    /// - Returns: ロード完了で返ったなら `true`、タイムアウトで返ったなら `false`
    @discardableResult
    static func wait(
        timeout: TimeInterval,
        start: (@escaping () -> Void) -> Void
    ) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let gate = ResumeOnce(continuation)
            start { gate.fire(completedInTime: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                gate.fire(completedInTime: false)
            }
        }
    }
}

/// 「先に来た方で1回だけ continuation を再開する」ためのゲート。
/// ロード完了とタイムアウトのどちらが先でも二重 resume させない。
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func fire(completedInTime: Bool) {
        let pending: CheckedContinuation<Bool, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: completedInTime)
    }
}
