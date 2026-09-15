//
//  AppOpenAdManager.swift
//  voicedocs
//
//  アプリ起動（App Open）広告。
//
//  voicedocs は IAP がゼロで AdMob 広告が唯一の収益源。実測 eCPM は
//  app_open がバナーの約20倍なので、無いフォーマットを1つ足す効果がいちばん大きい。
//
//  実装で外せない点（他プロダクトで実際に失敗している）:
//  - **ロード待ちを必ず入れる。** App Open の取得には通常1〜2秒かかるため、
//    「未ロードなら即諦める」実装だと起動時にほぼ間に合わず表示率が0.2%まで落ちる。
//    ここでは最大 `maxLoadWait` 秒（5秒）待つ。
//  - **起動N回に1回に絞る。** 毎起動で出すのは体験を壊す。
//  - **カウンタキーは広告専用。** 他機能（利用回数カウント等）と共有すると、
//    広告の表示機会が消えたり他機能が誤発火したりする。
//  - **表示されうる起動回だけプリロードする。** ゲートを通らない起動でロードすると
//    リクエストの無駄打ちになり、充填率の見え方も壊れる。
//  - **録音中・文字起こし中は出さない。** voicedocs は背景録音ができるので、
//    フォアグラウンド復帰時に録音画面へ広告がかぶりうる。ここが最大の地雷。
//

import GoogleMobileAds
import UIKit

@MainActor
final class AppOpenAdManager: NSObject {

    /// このクラス専用の永続化キー（他機能と共有しないこと）
    private enum Keys {
        static let launchCount = "ads.appOpen.launchCount"
    }

    /// 何回に1回表示するか
    private let showEveryNthLaunch: Int
    /// ロード待ちの上限（秒）。3〜5秒の範囲で運用する
    private let maxLoadWait: TimeInterval

    private let adUnitID: String
    private let coordinator: AdPresentationCoordinator
    private let defaults: UserDefaults
    /// 課金ユーザー判定。voicedocs は現状 IAP がゼロなので常に false。
    /// 将来 IAP を入れたらここを差し替えるだけで除外できる。
    private let isPremiumUser: () -> Bool
    /// 録音中・文字起こし中か
    private let isAudioBusy: () -> Bool

    private var appOpenAd: GADAppOpenAd?
    private var isLoading = false

    /// 広告ユニットIDが設定されていない場合はこのマネージャ自体を無効にする。
    /// **仮IDでは絶対に動かさない**（配信も計測も壊れるため）。
    private var isEnabled: Bool { !adUnitID.isEmpty }

    init(
        adUnitID: String,
        coordinator: AdPresentationCoordinator = .shared,
        defaults: UserDefaults = .standard,
        showEveryNthLaunch: Int = 5,
        maxLoadWait: TimeInterval = 5,
        isPremiumUser: @escaping () -> Bool = { false },
        isAudioBusy: @escaping () -> Bool = { AudioActivityRegistry.shared.isBusy }
    ) {
        self.adUnitID = adUnitID
        self.coordinator = coordinator
        self.defaults = defaults
        self.showEveryNthLaunch = max(1, showEveryNthLaunch)
        self.maxLoadWait = maxLoadWait
        self.isPremiumUser = isPremiumUser
        self.isAudioBusy = isAudioBusy
        super.init()
    }

    // MARK: - 表示ゲート

    /// この起動回で表示対象かどうかを判定し、カウンタを1つ進める。
    /// カウンタは「表示機会があった起動」でのみ進めるので、`showEveryNthLaunch` が
    /// そのまま体感の間隔になる。
    func consumeLaunchGate() -> Bool {
        let next = defaults.integer(forKey: Keys.launchCount) + 1
        defaults.set(next, forKey: Keys.launchCount)
        return next % showEveryNthLaunch == 0
    }

    /// いま広告を出してよい状態か（ゲート判定より前に弾くべき条件）。
    /// テストから直接叩けるよう internal にしてある。
    func isPresentableNow() -> Bool {
        guard isEnabled else {
            AppLogger.ads.debug("AppOpen skipped: ad unit ID is not configured")
            return false
        }
        guard !isPremiumUser() else {
            AppLogger.ads.debug("AppOpen skipped: premium user")
            return false
        }
        guard !isAudioBusy() else {
            AppLogger.ads.debug("AppOpen skipped: recording or transcription in progress")
            return false
        }
        guard coordinator.canPresent(.appOpen) else { return false }
        return true
    }

    // MARK: - 表示

    /// 起動 / フォアグラウンド復帰のタイミングで呼ぶ。
    ///
    /// ゲートを通った回**だけ**ロードを走らせる（無駄打ちを避けるため）。
    /// ロードは最大 `maxLoadWait` 秒待つ。間に合わなければ諦めるが、
    /// 取得済みの広告は次の機会に使う。
    func showIfEligible() async {
        guard isPresentableNow() else { return }
        guard consumeLaunchGate() else {
            AppLogger.ads.debug("AppOpen skipped: launch gate not reached")
            return
        }

        if appOpenAd == nil {
            await loadAd(timeout: maxLoadWait)
        }

        // 待っている間に状況が変わっている可能性があるので再チェック
        guard isPresentableNow(), let ad = appOpenAd else {
            AppLogger.ads.debug("AppOpen skipped: no ad available within \(self.maxLoadWait, privacy: .public)s")
            return
        }
        guard let presenter = UIApplication.shared.topMostViewController() else {
            AppLogger.ads.debug("AppOpen skipped: no presenting view controller")
            return
        }

        appOpenAd = nil
        coordinator.willPresent(.appOpen)
        ad.present(fromRootViewController: presenter)
    }

    // MARK: - ロード

    /// 広告をロードし、最大 `timeout` 秒だけ待つ。
    ///
    /// タイムアウトしても**ロード自体はキャンセルしない**。遅れて届いた広告は
    /// `appOpenAd` に保持して次の機会に使う（リクエストを無駄打ちしないため）。
    private func loadAd(timeout: TimeInterval) async {
        guard isEnabled, !isLoading else { return }
        isLoading = true

        let unitID = adUnitID
        await AdLoadWaiter.wait(timeout: timeout) { done in
            GADAppOpenAd.load(withAdUnitID: unitID, request: GADRequest()) { [weak self] ad, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        AppLogger.ads.error("AppOpen load failed: \(error.localizedDescription, privacy: .public)")
                    }
                    if let ad {
                        ad.fullScreenContentDelegate = self
                        self.appOpenAd = ad
                    }
                }
                done()
            }
        }
    }

    private func finishPresentation() {
        coordinator.didDismiss(.appOpen)
        appOpenAd = nil
    }
}

// MARK: - GADFullScreenContentDelegate

extension AppOpenAdManager: GADFullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        MainActor.assumeIsolated { finishPresentation() }
    }

    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        AppLogger.ads.error("AppOpen failed to present: \(error.localizedDescription, privacy: .public)")
        MainActor.assumeIsolated { finishPresentation() }
    }
}
