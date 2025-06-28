import GoogleMobileAds
import UIKit

class InterstitialAdManager: NSObject, ObservableObject {
    private var interstitialAd: GADInterstitialAd?
    private let adUnitID: String
    @Published var isAdLoaded = false
    @Published var isAdLoading = false
    
    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init()
        loadInterstitialAd()
    }
    
    func loadInterstitialAd() {
        guard !isAdLoading else { return }
        
        isAdLoading = true
        let request = GADRequest()
        
        GADInterstitialAd.load(withAdUnitID: adUnitID, request: request) { [weak self] ad, error in
            DispatchQueue.main.async {
                self?.isAdLoading = false
                
                if let error = error {
                    print("Failed to load interstitial ad with error: \(error.localizedDescription)")
                    self?.isAdLoaded = false
                    return
                }
                
                self?.interstitialAd = ad
                self?.interstitialAd?.fullScreenContentDelegate = self
                self?.isAdLoaded = true
                print("Interstitial ad loaded successfully")
            }
        }
    }
    
    func showInterstitialAd(completion: @escaping () -> Void) {
        guard let interstitialAd = interstitialAd else {
            print("Interstitial ad not loaded")
            completion()
            return
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("Unable to find root view controller")
            completion()
            return
        }
        
        // 広告表示後のコールバックを保存
        self.onAdDismissed = completion
        
        interstitialAd.present(fromRootViewController: rootViewController)
    }
    
    private var onAdDismissed: (() -> Void)?
}

// MARK: - GADFullScreenContentDelegate
extension InterstitialAdManager: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("Interstitial ad dismissed")
        interstitialAd = nil
        isAdLoaded = false
        
        // 広告が閉じられた後にコールバックを実行
        onAdDismissed?()
        onAdDismissed = nil
        
        // 次の広告を読み込み
        loadInterstitialAd()
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("Interstitial ad failed to present: \(error.localizedDescription)")
        interstitialAd = nil
        isAdLoaded = false
        
        // エラーの場合もコールバックを実行
        onAdDismissed?()
        onAdDismissed = nil
        
        // 次の広告を読み込み
        loadInterstitialAd()
    }
    
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("Interstitial ad will present")
    }
}