import GoogleMobileAds
import UIKit

class InterstitialAdManager: NSObject, ObservableObject {
    private var interstitialAd: GADInterstitialAd?
    private let adUnitID: String
    private let coordinator: AdPresentationCoordinator
    @Published var isAdLoaded = false
    @Published var isAdLoading = false
    
    init(adUnitID: String, coordinator: AdPresentationCoordinator = .shared) {
        self.coordinator = coordinator
        print("🚀 Initializing InterstitialAdManager")
        print("📱 Ad Unit ID received: \(adUnitID)")
        
        // 開発中はテスト用Ad Unit IDを使用
        #if DEBUG
        self.adUnitID = "ca-app-pub-3940256099942544/4411468910" // Google提供のテスト用インタースティシャルID
        print("🧪 Using test ad unit ID for DEBUG: \(self.adUnitID)")
        #else
        self.adUnitID = adUnitID
        print("🚀 Using production ad unit ID: \(self.adUnitID)")
        #endif
        
        super.init()
        
        // GADMobileAdsの初期化状態を確認
        let initStatus = GADMobileAds.sharedInstance().initializationStatus
        print("📡 GADMobileAds initialization status: \(initStatus.description)")
        
        loadInterstitialAd()
    }
    
    func loadInterstitialAd() {
        guard !isAdLoading else { 
            print("🚫 Ad already loading, skipping request")
            return 
        }
        
        print("🔄 Starting to load interstitial ad...")
        print("📱 Ad Unit ID: \(adUnitID)")
        
        isAdLoading = true
        let request = GADRequest()
        
        print("📡 Making GADInterstitialAd.load request...")
        GADInterstitialAd.load(withAdUnitID: adUnitID, request: request) { [weak self] ad, error in
            DispatchQueue.main.async {
                self?.isAdLoading = false
                
                if let error = error {
                    print("❌ Failed to load interstitial ad")
                    print("❌ Error: \(error.localizedDescription)")
                    print("❌ Error code: \(error._code)")
                    print("❌ Error domain: \(error._domain)")
                    self?.isAdLoaded = false
                    return
                }
                
                if ad != nil {
                    print("✅ Interstitial ad loaded successfully")
                    self?.interstitialAd = ad
                    self?.interstitialAd?.fullScreenContentDelegate = self
                    self?.isAdLoaded = true
                } else {
                    print("❌ Ad loaded but is nil")
                    self?.isAdLoaded = false
                }
            }
        }
    }
    
    /// インタースティシャルを表示する。
    ///
    /// 表示可否は必ず `AdPresentationCoordinator` を通す（アプリ起動広告と2枚重ならないようにするため）。
    /// 表示できない場合でも `completion` は必ず1回呼ばれる。
    @MainActor
    func showInterstitialAd(completion: @escaping () -> Void) {
        print("🎬 Attempting to show interstitial ad...")
        print("📊 Ad loaded status: \(isAdLoaded)")
        print("📊 Ad loading status: \(isAdLoading)")

        guard coordinator.canPresent(.interstitial) else {
            print("🚫 Interstitial blocked by AdPresentationCoordinator - executing completion directly")
            completion()
            return
        }

        guard let interstitialAd = interstitialAd else {
            print("❌ Interstitial ad not loaded - executing completion directly")
            completion()
            return
        }

        guard let presenter = UIApplication.shared.topMostViewController() else {
            print("❌ Unable to find presenting view controller - executing completion directly")
            completion()
            return
        }

        print("✅ Found presenting view controller, presenting ad...")
        // 広告表示後のコールバックを保存
        self.onAdDismissed = completion
        coordinator.willPresent(.interstitial)

        interstitialAd.present(fromRootViewController: presenter)
    }

    private var onAdDismissed: (() -> Void)?

    /// 表示終了時の後始末。閉じられた場合も表示失敗の場合も必ずここを通す。
    @MainActor
    private func finishPresentation() {
        coordinator.didDismiss(.interstitial)
        interstitialAd = nil
        isAdLoaded = false

        onAdDismissed?()
        onAdDismissed = nil

        loadInterstitialAd()
    }
}

// MARK: - GADFullScreenContentDelegate
extension InterstitialAdManager: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("📱 Interstitial ad dismissed by user")
        MainActor.assumeIsolated { finishPresentation() }
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("❌ Interstitial ad failed to present")
        print("❌ Presentation error: \(error.localizedDescription)")
        print("❌ Error code: \(error._code)")
        MainActor.assumeIsolated { finishPresentation() }
    }
    
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("📱 Interstitial ad will present")
    }
    
    func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        print("📊 Interstitial ad recorded impression")
    }
}