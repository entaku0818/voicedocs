//
//  AdMobConfigurationTests.swift
//  voicedocsTests
//
//  「出荷される AdMob 設定が本番のものになっているか」の回帰テスト。
//
//  実際に起きた事故:
//  Info.plist の `GADApplicationIdentifier` が Google のテスト用アプリID
//  (`ca-app-pub-3940256099942544~1458002511`) のまま App Store に出荷されていた。
//  広告ユニットIDは本番なのにアプリIDだけテスト用という食い違いで、
//  ビルドは通るしクラッシュもしないため、レビューでもテストでも気づけなかった。
//  ここで固定して二度と起きないようにする。
//

import XCTest
@testable import voicedocs

final class AdMobConfigurationTests: XCTestCase {

    /// 本番のパブリッシャID（アプリIDもユニットIDもこの配下にある）
    private let productionPublisher = "ca-app-pub-3484697221349891"

    private func infoPlistValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// CI（scripts/ios-ci.sh）は gitignore の Prod.xcconfig を空値のダミーで生成するため、
    /// xcconfig 由来のユニットIDを検証するテストはその場合に限りスキップする
    private func skipIfCIDummyXcconfig() throws {
        if ProcessInfo.processInfo.environment["VOICEDOCS_CI_DUMMY_XCCONFIG"] == "1" {
            throw XCTSkip("CI のダミー Prod.xcconfig ではユニットIDが空のためスキップ")
        }
    }

    // MARK: - アプリID

    func testGADApplicationIdentifier_isProductionAppID() {
        XCTAssertEqual(
            infoPlistValue("GADApplicationIdentifier"),
            "ca-app-pub-3484697221349891~7991961384"
        )
    }

    func testGADApplicationIdentifier_isNotAGoogleTestID() {
        let appID = infoPlistValue("GADApplicationIdentifier") ?? ""
        XCTAssertFalse(
            AdMobTestIdentifiers.isTestIdentifier(appID),
            "テスト用アプリIDが出荷されようとしている: \(appID)"
        )
    }

    // MARK: - 広告ユニットID

    /// 3フォーマット分のユニットIDが揃っていて、すべて本番パブリッシャ配下であること
    func testAdUnitIDs_areAllProductionAndNonEmpty() throws {
        try skipIfCIDummyXcconfig()
        let units = [
            "ADMOB_KEY": "ca-app-pub-3484697221349891/1059868285",
            "ADMOB_BANNER_KEY": "ca-app-pub-3484697221349891/2727572784",
            "ADMOB_APP_OPEN_KEY": "ca-app-pub-3484697221349891/3522065691"
        ]

        for (key, expected) in units {
            let value = infoPlistValue(key) ?? ""
            XCTAssertEqual(value, expected, "\(key) が期待した本番ユニットIDと違う")
            XCTAssertFalse(
                AdMobTestIdentifiers.isTestIdentifier(value),
                "\(key) にテスト用IDが入っている"
            )
        }
    }

    /// アプリIDとユニットIDのパブリッシャが一致していること（今回の事故の本質）
    func testAppIDAndAdUnitIDs_shareTheSamePublisher() throws {
        try skipIfCIDummyXcconfig()
        let appID = infoPlistValue("GADApplicationIdentifier") ?? ""
        XCTAssertTrue(appID.hasPrefix(productionPublisher), "アプリIDのパブリッシャが違う: \(appID)")

        for key in ["ADMOB_KEY", "ADMOB_BANNER_KEY", "ADMOB_APP_OPEN_KEY"] {
            let value = infoPlistValue(key) ?? ""
            XCTAssertTrue(
                value.hasPrefix(productionPublisher + "/"),
                "\(key) のパブリッシャがアプリIDと一致しない: \(value)"
            )
        }
    }

    // MARK: - sanitize

    /// リリースビルド相当ではテスト用IDを通さない（フォーマットを無効にして事故を止める）
    func testSanitize_inReleaseBuild_rejectsTestIdentifiers() {
        let sanitized = AdMobKeys.sanitize(
            AdMobTestIdentifiers.Debug.appOpen,
            allowingTestIdentifiers: false
        )
        XCTAssertEqual(sanitized, "")
    }

    /// DEBUGビルド相当ではテスト用IDを通す（ローカル動作確認のため）
    func testSanitize_inDebugBuild_allowsTestIdentifiers() {
        let sanitized = AdMobKeys.sanitize(
            AdMobTestIdentifiers.Debug.appOpen,
            allowingTestIdentifiers: true
        )
        XCTAssertEqual(sanitized, AdMobTestIdentifiers.Debug.appOpen)
    }

    /// 本番IDはどちらのビルドでもそのまま通る
    func testSanitize_passesProductionIdentifiersThrough() {
        let production = "ca-app-pub-3484697221349891/3522065691"
        XCTAssertEqual(AdMobKeys.sanitize(production, allowingTestIdentifiers: false), production)
        XCTAssertEqual(AdMobKeys.sanitize(production, allowingTestIdentifiers: true), production)
    }

    /// xcconfig に定義が無いと `$(...)` が未展開で入るので空に倒す
    func testSanitize_rejectsUnexpandedBuildSetting() {
        XCTAssertEqual(AdMobKeys.sanitize("$(ADMOB_APP_OPEN_KEY)"), "")
    }

    func testSanitize_trimsWhitespaceAndRejectsEmpty() {
        XCTAssertEqual(AdMobKeys.sanitize("   "), "")
        XCTAssertEqual(AdMobKeys.sanitize("  ca-app-pub-3484697221349891/1 "), "ca-app-pub-3484697221349891/1")
    }

    // MARK: - 読み込み

    /// `AdMobKeys.load()` が Info.plist の3つを読めていること
    func testLoad_readsAllThreeUnitsFromInfoPlist() throws {
        try skipIfCIDummyXcconfig()
        let config = AdMobKeys.load()

        XCTAssertFalse(config.interstitialAdUnitID.isEmpty)
        XCTAssertFalse(config.bannerAdUnitID.isEmpty)
        XCTAssertFalse(config.appOpenAdUnitID.isEmpty, "App Open のユニットIDが読めていない")
    }
}
