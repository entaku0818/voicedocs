import SwiftUI

// AdMob設定用の環境値
struct AdMobConfig {
    let interstitialAdUnitID: String
    let bannerAdUnitID: String
}

// Environment Key for AdMob configuration
struct AdMobConfigKey: EnvironmentKey {
    static let defaultValue = AdMobConfig(
        interstitialAdUnitID: "",
        bannerAdUnitID: ""
    )
}

extension EnvironmentValues {
    var admobConfig: AdMobConfig {
        get { self[AdMobConfigKey.self] }
        set { self[AdMobConfigKey.self] = newValue }
    }
}