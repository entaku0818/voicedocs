//
//  UIApplication+TopViewController.swift
//  voicedocs
//
//  全画面広告の presenting view controller を決めるためのヘルパー。
//
//  `connectedScenes.first?.windows.first?.rootViewController` を直接使うと、
//  - 複数シーン（iPad / Stage Manager）で非アクティブなシーンを掴む
//  - シート表示中に「すでに presented している VC」から present しようとして失敗する
//  という2つの理由で広告表示が落ちる。ここでアクティブなシーンの keyWindow から
//  最前面の VC までたどる。
//

import UIKit

extension UIApplication {
    /// 現在最前面に出ている view controller（広告の presenter に使う）
    func topMostViewController() -> UIViewController? {
        let activeScene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard let window = activeScene?.windows.first(where: \.isKeyWindow)
            ?? activeScene?.windows.first,
              var top = window.rootViewController else {
            return nil
        }

        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
