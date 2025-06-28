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
      print("🚀 AppDelegate.application didFinishLaunchingWithOptions called")
      FirebaseApp.configure()
      GADMobileAds.sharedInstance().start(completionHandler: { status in
          print("📡 GADMobileAds.start completed with status: \(status.description)")
      })
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
        print("🚀 SpeechRecognitionApp.init() called")
        let environmentConfig = loadEnvironmentVariables()
        self.admobUnitId = environmentConfig.admobKey
        self.admobBannerUnitId = environmentConfig.admobBannerKey
        print("📱 AdMob Interstitial ID loaded: \(admobUnitId ?? "nil")")
        print("📱 AdMob Banner ID loaded: \(admobBannerUnitId ?? "nil")")
    }

    var body: some Scene {
        print("🏗️ SpeechRecognitionApp.body called")
        return WindowGroup {
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
        print("🔍 Loading environment variables...")
        
        let bundleAdmobKey = Bundle.main.object(forInfoDictionaryKey: "ADMOB_KEY") as? String
        print("📦 Bundle ADMOB_KEY: \(bundleAdmobKey ?? "nil")")
        
        let bundleAdmobBannerKey = Bundle.main.object(forInfoDictionaryKey: "ADMOB_BANNER_KEY") as? String
        print("📦 Bundle ADMOB_BANNER_KEY: \(bundleAdmobBannerKey ?? "nil")")
        
        let processAdmobKey = ProcessInfo.processInfo.environment["ADMOB_KEY"]
        print("🌍 Process environment ADMOB_KEY: \(processAdmobKey ?? "nil")")
        
        let processAdmobBannerKey = ProcessInfo.processInfo.environment["ADMOB_BANNER_KEY"]
        print("🌍 Process environment ADMOB_BANNER_KEY: \(processAdmobBannerKey ?? "nil")")
        
        guard let admobKey = bundleAdmobKey ?? processAdmobKey else {
            print("❌ ADMOB_KEY not found in bundle or environment")
            fatalError("ADMOB_KEY environment variable is missing")
        }
        
        guard let admobBannerKey = bundleAdmobBannerKey ?? processAdmobBannerKey else {
            print("❌ ADMOB_BANNER_KEY not found in bundle or environment")
            fatalError("ADMOB_BANNER_KEY environment variable is missing")
        }
        
        print("✅ Using ADMOB_KEY: \(admobKey)")
        print("✅ Using ADMOB_BANNER_KEY: \(admobBannerKey)")
        return EnvironmentConfig(admobKey: admobKey, admobBannerKey: admobBannerKey)
    }

    struct EnvironmentConfig {
        let admobKey: String
        let admobBannerKey: String
    }
}

