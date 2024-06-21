//
//  voicedocsApp.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/01.
//

import SwiftUI
import FirebaseCore
import Firebase


class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()

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


    var body: some Scene {
        WindowGroup {
            VoiceMemoListView(voiceMemoController: VoiceMemoController())
        }
    }
}
