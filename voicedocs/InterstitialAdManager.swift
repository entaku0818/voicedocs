import GoogleMobileAds
import UIKit

class InterstitialAdManager: NSObject, ObservableObject {
    private var interstitialAd: GADInterstitialAd?
    private let adUnitID: String
    @Published var isAdLoaded = false
    @Published var isAdLoading = false
    
    init(adUnitID: String) {
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
    
    func showInterstitialAd(completion: @escaping () -> Void) {
        print("🎬 Attempting to show interstitial ad...")
        print("📊 Ad loaded status: \(isAdLoaded)")
        print("📊 Ad loading status: \(isAdLoading)")
        
        guard let interstitialAd = interstitialAd else {
            print("❌ Interstitial ad not loaded - executing completion directly")
            completion()
            return
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("❌ Unable to find root view controller - executing completion directly")
            completion()
            return
        }
        
        print("✅ Found root view controller, presenting ad...")
        // 広告表示後のコールバックを保存
        self.onAdDismissed = completion
        
        interstitialAd.present(fromRootViewController: rootViewController)
    }
    
    private var onAdDismissed: (() -> Void)?
}

// MARK: - GADFullScreenContentDelegate
extension InterstitialAdManager: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("📱 Interstitial ad dismissed by user")
        interstitialAd = nil
        isAdLoaded = false
        
        // 広告が閉じられた後にコールバックを実行
        print("🔄 Executing completion callback...")
        onAdDismissed?()
        onAdDismissed = nil
        
        // 次の広告を読み込み
        print("🔄 Loading next interstitial ad...")
        loadInterstitialAd()
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("❌ Interstitial ad failed to present")
        print("❌ Presentation error: \(error.localizedDescription)")
        print("❌ Error code: \(error._code)")
        interstitialAd = nil
        isAdLoaded = false
        
        // エラーの場合もコールバックを実行
        print("🔄 Executing completion callback after error...")
        onAdDismissed?()
        onAdDismissed = nil
        
        // 次の広告を読み込み
        print("🔄 Loading next interstitial ad after error...")
        loadInterstitialAd()
    }
    
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("📱 Interstitial ad will present")
    }
    
    func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        print("📊 Interstitial ad recorded impression")
    }
}