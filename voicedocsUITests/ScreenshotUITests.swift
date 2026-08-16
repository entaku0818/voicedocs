//
//  ScreenshotUITests.swift
//  voicedocsUITests
//
//  App Store 用スクリーンショットの撮影テスト。
//
//  通常のテスト実行に巻き込まれないよう、環境変数 SCREENSHOT_MODE=1 のときだけ実行する
//  （voicedocsUITests は issue #31 で完走しない既知問題があるため、
//   ハーネスの `-only-testing:voicedocsTests` からは元々外れている）。
//
//  データは事前に fastlane/screenshots_src/seed_data.py でシミュレータの
//  Core Data ストアへ投入しておくこと。このテストは撮影と画面遷移だけを担当する。
//
//  AIノートは「保存済みを読み込んで表示」ではなく、その場で実際に生成させて撮る。
//  理由: fetchVoiceMemo(id:) が aiTranscriptionText を復元していないため、
//        詳細画面に入ると保存済みノートが空で表示される（issue #32）。
//
//  撮った PNG は XCTAttachment として .xcresult に残す。ホスト側からは
//  `xcrun xcresulttool export attachments` で取り出す（take_screenshots.sh がやる）。
//

import XCTest

final class ScreenshotUITests: XCTestCase {

    private var isScreenshotMode: Bool {
        ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
    }

    private let seededMemoTitle = "週次定例｜開発チーム"

    /// AIノートのオンデバイス生成を待つ上限。
    /// シミュレータでは返ってこないので、長く待たずに諦めて次のスクショへ進む。
    private let aiGenerationTimeout: TimeInterval = 90

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshots() throws {
        try XCTSkipUnless(isScreenshotMode, "SCREENSHOT_MODE=1 のときだけ撮影する")

        let app = XCUIApplication()
        app.launch()

        // ① 一覧
        XCTAssertTrue(app.staticTexts[seededMemoTitle].waitForExistence(timeout: 30),
                      "シードデータが見つからない。seed_data.py を先に実行すること")
        settle()
        save(name: "01_list")

        // ② 詳細（文字起こし結果）
        app.staticTexts[seededMemoTitle].tap()
        XCTAssertTrue(app.staticTexts["文字起こし結果"].waitForExistence(timeout: 30))
        settle()
        save(name: "02_detail_transcription")

        // ③ AIノート
        //
        // 生成完了まで撮れるのが理想だが、シミュレータでは
        // SystemLanguageModel.default.isAvailable が true でも実際の生成が返ってこない
        // （300秒待っても「保存」ボタンが出ない）。実機でしか生成後の状態は撮れない。
        // そのため生成は試みるが、終わらなければ未生成状態のセクションを撮って先へ進む。
        let generateButton = app.buttons["AIノートを生成"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 30), "AIノートの生成ボタンが見つからない")
        scrollUntilHittable(app: app, element: generateButton)
        settle()
        save(name: "03_ai_note_idle")

        generateButton.tap()
        let saveButton = app.buttons["保存"]
        if saveButton.waitForExistence(timeout: aiGenerationTimeout) {
            scrollUntilHittable(app: app, element: saveButton)
            settle()
            save(name: "03_ai_note")
        } else {
            // 生成が返ってこないケース。ここで失敗させると他のスクショまで撮れなくなるので、
            // 記録だけ残して続行する。生成後の絵が要るなら実機で撮ること。
            print("SCREENSHOT_WARNING AIノートの生成が \(aiGenerationTimeout) 秒で完了しなかった（実機で撮り直しが必要）")
            save(name: "03_ai_note_generating")
        }

        // ④ 録音画面
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts[seededMemoTitle].waitForExistence(timeout: 30))
        settle()
        let recordButton = app.buttons["録音"]
        if recordButton.waitForExistence(timeout: 15) {
            recordButton.tap()
            _ = app.navigationBars["音声録音"].waitForExistence(timeout: 30)
            settle()
            save(name: "04_recording")
        }
    }

    // MARK: - Helpers

    /// アニメーションが終わってから撮るための待ち。
    /// これを入れないとナビゲーションタイトルが二重に写るなど、崩れたコマを掴む。
    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// 対象が画面内に来るまでスクロールする。
    private func scrollUntilHittable(app: XCUIApplication, element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            settle(0.8)
            swipes += 1
        }
    }

    private func save(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
