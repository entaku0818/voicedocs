//
//  voicedocsApp.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/01.
//

import SwiftUI
import Firebase
import os.log
import GoogleMobileAds

class AppDelegate: NSObject, UIApplicationDelegate {
  /// アプリ起動（App Open）広告。ユニットIDが未設定なら自動的に無効になる。
  private var appOpenAdManager: AppOpenAdManager?

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
      FirebaseApp.configure()

      #if DEBUG
      // 開発中は本番の広告を配信させない（無効traffic防止）
      let appOpenAdUnitID = AdMobTestIdentifiers.Debug.appOpen
      #else
      let appOpenAdUnitID = AdMobKeys.load().appOpenAdUnitID
      #endif
      let appOpenAdManager = AppOpenAdManager(adUnitID: appOpenAdUnitID)
      self.appOpenAdManager = appOpenAdManager

      // App Open はロードに1〜2秒かかるので、SDKの初期化完了を待ってから機会を判定する。
      GADMobileAds.sharedInstance().start { _ in
          Task { @MainActor in
              await appOpenAdManager.showIfEligible()
          }
      }

      // フォアグラウンド復帰時。`didBecomeActive` ではなく `willEnterForeground` を使うのは、
      // マイク権限ダイアログなどを閉じただけで誤発火させないため。
      NotificationCenter.default.addObserver(
          forName: UIApplication.willEnterForegroundNotification,
          object: nil,
          queue: .main
      ) { _ in
          Task { @MainActor in
              await appOpenAdManager.showIfEligible()
          }
      }

    #if DEBUG
      if FirebaseApp.app() != nil {
          AppLogger.ui.info("Firebase has been successfully configured.")
      } else {
          AppLogger.ui.error("Firebase configuration failed.")
      }
    Analytics.setAnalyticsCollectionEnabled(true)
    Analytics.setUserID("debug_user")
    AppLogger.ui.debug("Firebase Analytics debug logging is enabled")
      Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
    #endif

    return true
  }
}

@main
struct SpeechRecognitionApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    private let admobConfig: AdMobConfig

    init() {
        self.admobConfig = AdMobKeys.load()
    }

    var body: some Scene {
        WindowGroup {
            VoiceMemoListView(voiceMemoController: VoiceMemoController())
                .environment(\.admobConfig, admobConfig)
        }
    }
}
