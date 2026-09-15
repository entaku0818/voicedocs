//
//  AdLoadWaiterTests.swift
//  voicedocsTests
//
//  App Open 広告の「ロード待ち上限」のテスト。
//  待たない実装にすると起動時にロードが間に合わず表示率が0.2%まで落ちるため、
//  ここが崩れると収益が静かに死ぬ。
//

import XCTest
@testable import voicedocs

final class AdLoadWaiterTests: XCTestCase {

    /// ロードが間に合えば、タイムアウトを待たずに完了として返る
    func testWait_whenLoadCompletesInTime_returnsTrueQuickly() async {
        let started = Date()

        let completedInTime = await AdLoadWaiter.wait(timeout: 5) { done in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { done() }
        }

        XCTAssertTrue(completedInTime)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "タイムアウトを待たずに返るべき")
    }

    /// ロードが返ってこなくても、上限で打ち切って返る（無限に待たない）
    func testWait_whenLoadNeverCompletes_returnsFalseAfterTimeout() async {
        let started = Date()

        let completedInTime = await AdLoadWaiter.wait(timeout: 0.3) { _ in
            // done を呼ばない = 広告が返ってこないケース
        }

        let elapsed = Date().timeIntervalSince(started)
        XCTAssertFalse(completedInTime)
        XCTAssertGreaterThanOrEqual(elapsed, 0.25, "上限まで待つべき")
        XCTAssertLessThan(elapsed, 2.0, "上限を大きく超えて待ってはいけない")
    }

    /// タイムアウト後に遅れてロードが完了しても、二重 resume でクラッシュしない
    func testWait_whenLoadCompletesAfterTimeout_doesNotCrash() async {
        let completedInTime = await AdLoadWaiter.wait(timeout: 0.1) { done in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done() }
        }
        XCTAssertFalse(completedInTime)

        // 遅れて届いた done が走りきるのを待つ（ここでクラッシュしないことが本題）
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    /// done が複数回呼ばれても落ちない
    func testWait_whenDoneCalledMultipleTimes_doesNotCrash() async {
        let completedInTime = await AdLoadWaiter.wait(timeout: 5) { done in
            DispatchQueue.main.async {
                done()
                done()
                done()
            }
        }
        XCTAssertTrue(completedInTime)
    }
}
