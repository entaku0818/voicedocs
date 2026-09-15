import SwiftUI

// AdMob設定用の環境値
struct AdMobConfig {
    let interstitialAdUnitID: String
    let bannerAdUnitID: String
    /// アプリ起動（App Open）広告のユニットID。空なら App Open は無効。
    let appOpenAdUnitID: String

    init(interstitialAdUnitID: String, bannerAdUnitID: String, appOpenAdUnitID: String = "") {
        self.interstitialAdUnitID = interstitialAdUnitID
        self.bannerAdUnitID = bannerAdUnitID
        self.appOpenAdUnitID = appOpenAdUnitID
    }
}

// Environment Key for AdMob configuration
struct AdMobConfigKey: EnvironmentKey {
    static let defaultValue = AdMobConfig(
        interstitialAdUnitID: "",
        bannerAdUnitID: "",
        appOpenAdUnitID: ""
    )
}

extension EnvironmentValues {
    var admobConfig: AdMobConfig {
        get { self[AdMobConfigKey.self] }
        set { self[AdMobConfigKey.self] = newValue }
    }
}

/// Google が公開しているテスト用のパブリッシャID。
/// **本番ビルドにこのIDが混ざってはいけない**（配信も計測も壊れる）。
enum AdMobTestIdentifiers {
    static let publisherPrefix = "ca-app-pub-3940256099942544"

    /// Google提供のテスト用ID。
    ///
    /// `#if DEBUG` で囲ってあるため、**リリースビルドにはそもそもコンパイルされない**。
    /// 最適化任せにせず、テスト用IDが出荷され得ないことをコンパイル時に保証する。
    #if DEBUG
    enum Debug {
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
        static let banner = "ca-app-pub-3940256099942544/2934735716"
        static let appOpen = "ca-app-pub-3940256099942544/5662855259"
    }
    #endif

    /// テスト用パブリッシャのIDかどうか
    static func isTestIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(publisherPrefix)
    }
}

/// AdMob の広告ユニットIDを Info.plist / 環境変数から読む。
///
/// App Open は AppDelegate（SwiftUI の View 階層の外）から必要になるため、
/// View 用の `@Environment(\.admobConfig)` とは別にここから直接引けるようにしてある。
/// どちらも読み元はこの1箇所。
enum AdMobKeys {
    static func load() -> AdMobConfig {
        let config = AdMobConfig(
            interstitialAdUnitID: value(for: "ADMOB_KEY"),
            bannerAdUnitID: value(for: "ADMOB_BANNER_KEY"),
            appOpenAdUnitID: value(for: "ADMOB_APP_OPEN_KEY")
        )
        // 以前は未設定で fatalError していたが、広告の設定ミスでアプリを落とすのは割に合わない。
        // 該当フォーマットだけ無効にして、気づけるようログに残す。
        for (name, id) in [
            ("ADMOB_KEY", config.interstitialAdUnitID),
            ("ADMOB_BANNER_KEY", config.bannerAdUnitID),
            ("ADMOB_APP_OPEN_KEY", config.appOpenAdUnitID)
        ] where id.isEmpty {
            AppLogger.ads.error("\(name, privacy: .public) is not configured — that ad format is disabled")
        }
        return config
    }

    private static func value(for key: String) -> String {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let processValue = ProcessInfo.processInfo.environment[key]
        return sanitize(bundleValue ?? processValue ?? "")
    }

    /// 読み込んだIDを検証する。
    ///
    /// - xcconfig に定義が無いと `$(ADMOB_APP_OPEN_KEY)` が未展開のまま入るので空に倒す
    /// - **リリースビルドにテスト用IDが残っていたら空に倒す。**
    ///   テスト用アプリIDが本番に出荷されていた事故があるため、ここで最後に止める。
    ///   空になれば該当フォーマットは表示されなくなるが、間違ったIDで配信するよりはよい。
    static func sanitize(
        _ rawValue: String,
        allowingTestIdentifiers: Bool = isDebugBuild
    ) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        // 未展開のビルド設定変数
        guard !value.hasPrefix("$(") else { return "" }

        if !allowingTestIdentifiers, AdMobTestIdentifiers.isTestIdentifier(value) {
            AppLogger.ads.error("Test ad unit ID found in a release build — disabling this ad format")
            return ""
        }

        return value
    }

    /// DEBUGビルドかどうか。テストから解放ビルドの挙動も検証できるよう、
    /// `sanitize` は既定値としてこれを使いつつ明示的に上書きもできるようにしてある。
    static let isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
