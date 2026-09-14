//
//  AdPresentationCoordinator.swift
//  voicedocs
//
//  全画面広告（インタースティシャル / アプリ起動）の相互排他と表示間隔を一元管理する。
//
//  背景:
//  - voicedocs は IAP を持たず AdMob が唯一の収益源なので、広告は「出す」だけでなく
//    「出しすぎない」制御が要る。フォーマットごとに個別実装すると、
//    インタースティシャルとアプリ起動広告が連続して2枚出る事故が起きる。
//  - そのため全画面広告の表示可否は必ずこのクラスを通す。
//
//  カウンタ/タイムスタンプの永続化キーは**このクラス専用**にしてある。
//  他機能（利用回数カウント等）とキーを共有しないこと。共有すると、
//  広告の表示機会が他機能の都合で消えたり、逆に他機能が誤発火したりする。
//

import Foundation

/// 全画面広告の種類
enum FullScreenAdKind: String {
    case interstitial
    case appOpen
}

@MainActor
final class AdPresentationCoordinator {
    static let shared = AdPresentationCoordinator()

    /// このクラス専用の永続化キー（他機能と共有しないこと）
    private enum Keys {
        static let lastFullScreenAdShownAt = "ads.fullScreen.lastShownAt"
    }

    /// 全画面広告どうしの最低間隔。連続2枚を防ぐ最後の砦。
    private let minimumInterval: TimeInterval = 60

    private let defaults: UserDefaults

    /// いま全画面広告を表示中か（表示中は他フォーマットを一切通さない）
    private(set) var isPresenting = false

    /// 現在表示中の広告種別
    private(set) var presentingKind: FullScreenAdKind?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var lastShownAt: Date? {
        get {
            let timestamp = defaults.double(forKey: Keys.lastFullScreenAdShownAt)
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastFullScreenAdShownAt)
        }
    }

    /// この種別の全画面広告をいま出してよいか。
    /// - 他の全画面広告を表示中なら false（相互排他）
    /// - 直前の全画面広告から `minimumInterval` 未満なら false（連続表示防止）
    func canPresent(_ kind: FullScreenAdKind, now: Date = Date()) -> Bool {
        guard !isPresenting else {
            AppLogger.ads.debug("Ad rejected: \(kind.rawValue, privacy: .public) blocked by presenting ad")
            return false
        }
        if let lastShownAt, now.timeIntervalSince(lastShownAt) < minimumInterval {
            AppLogger.ads.debug("Ad rejected: \(kind.rawValue, privacy: .public) within cooldown")
            return false
        }
        return true
    }

    /// 表示直前に呼ぶ。以降 `didDismiss` まで他の全画面広告はブロックされる。
    func willPresent(_ kind: FullScreenAdKind, now: Date = Date()) {
        isPresenting = true
        presentingKind = kind
        lastShownAt = now
    }

    /// 表示終了（閉じられた / 表示に失敗した）時に必ず呼ぶ。
    func didDismiss(_ kind: FullScreenAdKind) {
        guard presentingKind == kind else { return }
        isPresenting = false
        presentingKind = nil
    }
}
