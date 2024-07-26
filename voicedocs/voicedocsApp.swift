//
//  voicedocsApp.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/01.
//

import SwiftUI
import FirebaseCore
import Firebase
import GoogleMobileAds

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
      FirebaseApp.configure()
      GADMobileAds.sharedInstance().start(completionHandler: nil)
    #if DEBUG
      if FirebaseApp.app() != nil {
          print("Firebase has been successfully configured.")
      } else {
          print("Firebase configuration failed.")
      }
    Analytics.setAnalyticsCollectionEnabled(true)
    Analytics.setUserID("debug_user")
    print("Firebase Analytics debug logging is enabled")
    #endif

    return true
  }
}

@main
struct SpeechRecognitionApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var admobUnitId: String!
    init() {
        let environmentConfig = loadEnvironmentVariables()
        self.admobUnitId = environmentConfig.admobKey
    }

    var body: some Scene {
        WindowGroup {
            VoiceMemoListView(voiceMemoController: VoiceMemoController(), admobKey: admobUnitId)
        }
    }
}

extension SpeechRecognitionApp {
    func loadEnvironmentVariables() -> EnvironmentConfig {

        guard let admobKey = Bundle.main.object(forInfoDictionaryKey: "ADMOB_KEY") as? String ?? ProcessInfo.processInfo.environment["ADMOB_KEY"]
        else {
            fatalError("One or more environment variables are missing")
        }

        return EnvironmentConfig(admobKey: admobKey)
    }

    struct EnvironmentConfig {
        let admobKey: String
    }
}

