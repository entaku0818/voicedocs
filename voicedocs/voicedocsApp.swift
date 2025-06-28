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
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
      FirebaseApp.configure()
      GADMobileAds.sharedInstance().start(completionHandler: nil)
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

