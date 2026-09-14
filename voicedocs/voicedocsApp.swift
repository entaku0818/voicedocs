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
      // Google提供のテスト用アプリ起動広告ID（ローカルでの動作確認用）
      let appOpenAdUnitID = "ca-app-pub-3940256099942544/5662855259"
      #else
      // 未発行なら空文字。AppOpenAdManager 側で丸ごと無効になる（仮IDは使わない）
      let appOpenAdUnitID = AdMobKeys.load().appOpenKey
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

    var admobUnitId: String!
    var admobBannerUnitId: String!
    init() {
        let environmentConfig = loadEnvironmentVariables()
        self.admobUnitId = environmentConfig.admobKey
        self.admobBannerUnitId = environmentConfig.admobBannerKey
    }

    var body: some Scene {
        WindowGroup {
            VoiceMemoListView(voiceMemoController: VoiceMemoController())
                .environment(\.admobConfig, AdMobConfig(
                    interstitialAdUnitID: admobUnitId,
                    bannerAdUnitID: admobBannerUnitId
                ))
        }
    }
}

/// AdMob の広告ユニットIDを Info.plist / 環境変数から読む。
///
/// App Open は AppDelegate（SwiftUI の App より先に動く）から必要になるため、
/// `SpeechRecognitionApp.loadEnvironmentVariables()` とは別にここから引けるようにしてある。
enum AdMobKeys {
    struct Keys {
        let interstitialKey: String
        let bannerKey: String
        /// 未発行の場合は空文字。空なら App Open 広告は丸ごと無効になる（仮IDは使わない）
        let appOpenKey: String
    }

    static func load() -> Keys {
        Keys(
            interstitialKey: value(for: "ADMOB_KEY"),
            bannerKey: value(for: "ADMOB_BANNER_KEY"),
            appOpenKey: value(for: "ADMOB_APP_OPEN_KEY")
        )
    }

    private static func value(for key: String) -> String {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let processValue = ProcessInfo.processInfo.environment[key]
        let resolved = bundleValue ?? processValue ?? ""
        // xcconfig に定義が無いと "$(ADMOB_APP_OPEN_KEY)" が展開されずそのまま入るため弾く
        return resolved.hasPrefix("$(") ? "" : resolved
    }
}

extension SpeechRecognitionApp {
    func loadEnvironmentVariables() -> EnvironmentConfig {
        let bundleAdmobKey = Bundle.main.object(forInfoDictionaryKey: "ADMOB_KEY") as? String
        let bundleAdmobBannerKey = Bundle.main.object(forInfoDictionaryKey: "ADMOB_BANNER_KEY") as? String
        let processAdmobKey = ProcessInfo.processInfo.environment["ADMOB_KEY"]
        let processAdmobBannerKey = ProcessInfo.processInfo.environment["ADMOB_BANNER_KEY"]
        
        guard let admobKey = bundleAdmobKey ?? processAdmobKey else {
            fatalError("ADMOB_KEY environment variable is missing")
        }
        
        guard let admobBannerKey = bundleAdmobBannerKey ?? processAdmobBannerKey else {
            fatalError("ADMOB_BANNER_KEY environment variable is missing")
        }
        
        return EnvironmentConfig(admobKey: admobKey, admobBannerKey: admobBannerKey)
    }

    struct EnvironmentConfig {
        let admobKey: String
        let admobBannerKey: String
    }
}

