//
//  AdPresentationCoordinatorTests.swift
//  voicedocsTests
//
//  全画面広告（インタースティシャル / アプリ起動）の相互排他と表示間隔のテスト。
//  「連続して2枚出る」事故がいちばん怖いので、そこを重点的に固定する。
//

import XCTest
@testable import voicedocs

@MainActor
final class AdPresentationCoordinatorTests: XCTestCase {

    private func makeCoordinator() -> (AdPresentationCoordinator, UserDefaults) {
        let suiteName = "AdPresentationCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AdPresentationCoordinator(defaults: defaults), defaults)
    }

    func testCanPresent_whenNothingShownYet_returnsTrue() {
        let (coordinator, _) = makeCoordinator()
        XCTAssertTrue(coordinator.canPresent(.interstitial))
        XCTAssertTrue(coordinator.canPresent(.appOpen))
    }

    /// 相互排他: インタースティシャル表示中はアプリ起動広告を通さない
    func testCanPresent_whileInterstitialIsPresenting_blocksAppOpen() {
        let (coordinator, _) = makeCoordinator()
        coordinator.willPresent(.interstitial)

        XCTAssertFalse(coordinator.canPresent(.appOpen))
        XCTAssertFalse(coordinator.canPresent(.interstitial))
    }

    /// 相互排他: アプリ起動広告表示中はインタースティシャルを通さない
    func testCanPresent_whileAppOpenIsPresenting_blocksInterstitial() {
        let (coordinator, _) = makeCoordinator()
        coordinator.willPresent(.appOpen)

        XCTAssertFalse(coordinator.canPresent(.interstitial))
    }

    /// 表示間隔: 閉じた直後でもクールダウン中は次の全画面広告を出さない
    func testCanPresent_immediatelyAfterDismiss_isBlockedByCooldown() {
        let (coordinator, _) = makeCoordinator()
        let now = Date()
        coordinator.willPresent(.interstitial, now: now)
        coordinator.didDismiss(.interstitial)

        XCTAssertFalse(coordinator.canPresent(.appOpen, now: now.addingTimeInterval(1)))
        XCTAssertFalse(coordinator.canPresent(.appOpen, now: now.addingTimeInterval(59)))
    }

    /// 表示間隔を過ぎたら再び出せる
    func testCanPresent_afterCooldownElapsed_returnsTrue() {
        let (coordinator, _) = makeCoordinator()
        let now = Date()
        coordinator.willPresent(.interstitial, now: now)
        coordinator.didDismiss(.interstitial)

        XCTAssertTrue(coordinator.canPresent(.appOpen, now: now.addingTimeInterval(61)))
    }

    /// 別種別の didDismiss で表示中フラグが誤って解除されないこと
    func testDidDismiss_withDifferentKind_doesNotReleaseLock() {
        let (coordinator, _) = makeCoordinator()
        coordinator.willPresent(.interstitial)
        coordinator.didDismiss(.appOpen)

        XCTAssertTrue(coordinator.isPresenting)
        XCTAssertFalse(coordinator.canPresent(.appOpen))
    }

    /// 永続化キーは広告専用。他機能とキーを共有していないことを明示的に固定する。
    func testWillPresent_persistsUnderDedicatedKey() {
        let (coordinator, defaults) = makeCoordinator()
        coordinator.willPresent(.interstitial)

        XCTAssertGreaterThan(defaults.double(forKey: "ads.fullScreen.lastShownAt"), 0)
        XCTAssertNil(defaults.object(forKey: "appUsageCount"))
    }
}
