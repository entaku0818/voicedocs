import SwiftUI
import GoogleMobileAds
import UIKit

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    let adSize: GADAdSize
    
    init(adUnitID: String, adSize: GADAdSize = GADAdSizeBanner) {
        self.adUnitID = adUnitID
        self.adSize = adSize
        print("🎯 BannerAdView init with adUnitID: \(adUnitID)")
    }
    
    func makeUIView(context: Context) -> GADBannerView {
        print("🏗️ Creating GADBannerView...")
        
        let bannerView = GADBannerView(adSize: adSize)
        
        // デバッグ用のテスト広告IDを使用
        #if DEBUG
        let testAdUnitID = AdMobTestIdentifiers.Debug.banner // Google提供のテスト用バナーID
        bannerView.adUnitID = testAdUnitID
        print("🧪 Using test banner ad unit ID: \(testAdUnitID)")
        #else
        bannerView.adUnitID = adUnitID
        print("🚀 Using production banner ad unit ID: \(adUnitID)")
        #endif
        
        bannerView.delegate = context.coordinator
        
        // ルートビューコントローラーを設定
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootViewController
            print("✅ Root view controller set for banner ad")
        } else {
            print("❌ Could not find root view controller for banner ad")
        }
        
        // 広告をロード
        let request = GADRequest()
        print("📡 Loading banner ad...")
        bannerView.load(request)
        
        return bannerView
    }
    
    func updateUIView(_ uiView: GADBannerView, context: Context) {
        // UIViewの更新が必要な場合はここで行う
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            print("✅ Banner ad loaded successfully")
        }
        
        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            print("❌ Banner ad failed to load")
            print("❌ Error: \(error.localizedDescription)")
        }
        
        func bannerViewDidRecordImpression(_ bannerView: GADBannerView) {
            print("📊 Banner ad recorded impression")
        }
        
        func bannerViewWillPresentScreen(_ bannerView: GADBannerView) {
            print("📱 Banner ad will present screen")
        }
        
        func bannerViewWillDismissScreen(_ bannerView: GADBannerView) {
            print("📱 Banner ad will dismiss screen")
        }
        
        func bannerViewDidDismissScreen(_ bannerView: GADBannerView) {
            print("📱 Banner ad did dismiss screen")
        }
    }
}
