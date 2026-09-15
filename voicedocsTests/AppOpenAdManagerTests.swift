//
//  AppOpenAdManagerTests.swift
//  voicedocsTests
//
//  アプリ起動（App Open）広告の表示ゲートのテスト。
//  他プロダクトで実際に起きた失敗（表示率0.2%、カウンタキーの共有、
//  録音中への広告かぶせ）をそのまま回帰テストにしてある。
//

import XCTest
@testable import voicedocs

@MainActor
final class AppOpenAdManagerTests: XCTestCase {

    private let realAdUnitID = "ca-app-pub-0000000000000000/1111111111"

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppOpenAdManagerTests.\(UUID().uuidString)")!
    }

    private func makeManager(
        adUnitID: String? = nil,
        defaults: UserDefaults? = nil,
        coordinator: AdPresentationCoordinator? = nil,
        showEveryNthLaunch: Int = 5,
        isPremiumUser: @escaping () -> Bool = { false },
        isAudioBusy: @escaping () -> Bool = { false }
    ) -> AppOpenAdManager {
        AppOpenAdManager(
            adUnitID: adUnitID ?? realAdUnitID,
            coordinator: coordinator ?? AdPresentationCoordinator(defaults: makeDefaults()),
            defaults: defaults ?? makeDefaults(),
            showEveryNthLaunch: showEveryNthLaunch,
            isPremiumUser: isPremiumUser,
            isAudioBusy: isAudioBusy
        )
    }

    // MARK: - 表示間隔ゲート

    /// 起動5回に1回だけ表示対象になる
    func testConsumeLaunchGate_showsOnEveryFifthLaunch() {
        let manager = makeManager(showEveryNthLaunch: 5)

        let results = (1...10).map { _ in manager.consumeLaunchGate() }

        XCTAssertEqual(results, [false, false, false, false, true,
                                 false, false, false, false, true])
    }

    /// 毎起動表示（N=1）も壊れていないこと
    func testConsumeLaunchGate_withIntervalOne_showsEveryLaunch() {
        let manager = makeManager(showEveryNthLaunch: 1)

        XCTAssertTrue(manager.consumeLaunchGate())
        XCTAssertTrue(manager.consumeLaunchGate())
    }

    /// 0以下を渡しても0除算やゼロ間隔にならない
    func testConsumeLaunchGate_withInvalidInterval_fallsBackToEveryLaunch() {
        let manager = makeManager(showEveryNthLaunch: 0)

        XCTAssertTrue(manager.consumeLaunchGate())
    }

    // MARK: - カウンタキー

    /// カウンタは広告専用キーに書き、他機能のキーを汚さない
    /// （他プロダクトで `appUsageCount` を共有して表示機会が消えた事故の回帰テスト）
    func testConsumeLaunchGate_usesDedicatedKey() {
        let defaults = makeDefaults()
        let manager = makeManager(defaults: defaults)

        _ = manager.consumeLaunchGate()

        XCTAssertEqual(defaults.integer(forKey: "ads.appOpen.launchCount"), 1)
        XCTAssertNil(defaults.object(forKey: "appUsageCount"))
        XCTAssertNil(defaults.object(forKey: "ads.fullScreen.lastShownAt"))
    }

    // MARK: - 表示可否

    func testIsPresentableNow_withNormalState_returnsTrue() {
        XCTAssertTrue(makeManager().isPresentableNow())
    }

    /// ユニットID未設定なら丸ごと無効（仮IDでは動かさない）
    func testIsPresentableNow_withEmptyAdUnitID_returnsFalse() {
        XCTAssertFalse(makeManager(adUnitID: "").isPresentableNow())
    }

    /// 課金ユーザーには出さない
    func testIsPresentableNow_forPremiumUser_returnsFalse() {
        XCTAssertFalse(makeManager(isPremiumUser: { true }).isPresentableNow())
    }

    /// 録音中・文字起こし中には絶対に出さない
    func testIsPresentableNow_whileAudioBusy_returnsFalse() {
        XCTAssertFalse(makeManager(isAudioBusy: { true }).isPresentableNow())
    }

    /// インタースティシャル表示中には出さない（相互排他）
    func testIsPresentableNow_whileInterstitialIsPresenting_returnsFalse() {
        let coordinator = AdPresentationCoordinator(defaults: makeDefaults())
        let manager = makeManager(coordinator: coordinator)
        coordinator.willPresent(.interstitial)

        XCTAssertFalse(manager.isPresentableNow())
    }

    // MARK: - 録音レジストリ連携

    /// デフォルトの `isAudioBusy` が AudioActivityRegistry を見ていること
    func testIsPresentableNow_readsAudioActivityRegistryByDefault() {
        let registry = AudioActivityRegistry.shared
        registry.reset()
        let manager = AppOpenAdManager(
            adUnitID: realAdUnitID,
            coordinator: AdPresentationCoordinator(defaults: makeDefaults()),
            defaults: makeDefaults()
        )
        XCTAssertTrue(manager.isPresentableNow())

        let recorder = NSObject()
        registry.update(isActive: true, for: recorder)
        defer { registry.reset() }

        XCTAssertFalse(manager.isPresentableNow())
    }
}
