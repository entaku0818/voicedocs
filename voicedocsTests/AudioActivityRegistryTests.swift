//
//  AudioActivityRegistryTests.swift
//  voicedocsTests
//
//  「録音中・文字起こし中に全画面広告を出さない」の土台になるレジストリのテスト。
//

import XCTest
@testable import voicedocs

final class AudioActivityRegistryTests: XCTestCase {

    func testIsBusy_initially_isFalse() {
        let registry = AudioActivityRegistry()
        XCTAssertFalse(registry.isBusy)
    }

    func testIsBusy_whileOneOwnerActive_isTrue() {
        let registry = AudioActivityRegistry()
        let owner = NSObject()

        registry.update(isActive: true, for: owner)
        XCTAssertTrue(registry.isBusy)

        registry.update(isActive: false, for: owner)
        XCTAssertFalse(registry.isBusy)
    }

    /// 録音と文字起こしが同時に走っても、片方が終わっただけでは busy が解けない
    func testIsBusy_withMultipleOwners_staysTrueUntilAllFinish() {
        let registry = AudioActivityRegistry()
        let recorder = NSObject()
        let transcriber = NSObject()

        registry.update(isActive: true, for: recorder)
        registry.update(isActive: true, for: transcriber)
        registry.update(isActive: false, for: recorder)

        XCTAssertTrue(registry.isBusy, "文字起こしがまだ走っているので busy のままであるべき")

        registry.update(isActive: false, for: transcriber)
        XCTAssertFalse(registry.isBusy)
    }

    /// 同じ owner が二重に開始を申告しても、1回の終了で解ける
    func testIsBusy_withDuplicateStart_clearsOnSingleStop() {
        let registry = AudioActivityRegistry()
        let owner = NSObject()

        registry.update(isActive: true, for: owner)
        registry.update(isActive: true, for: owner)
        registry.update(isActive: false, for: owner)

        XCTAssertFalse(registry.isBusy)
    }

    /// deinit から使う ObjectIdentifier 版でも解除できる
    func testUpdateWithObjectIdentifier_clearsEntry() {
        let registry = AudioActivityRegistry()
        let owner = NSObject()
        let id = ObjectIdentifier(owner)

        registry.update(isActive: true, for: owner)
        registry.update(isActive: false, id: id)

        XCTAssertFalse(registry.isBusy)
    }
}
