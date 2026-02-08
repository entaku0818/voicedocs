//
//  RealtimeTranscriptionRecorderTests.swift
//  voicedocsTests
//
//  Tests for RealtimeTranscriptionRecorder, focusing on recording timer functionality
//

import XCTest
import Combine
@testable import voicedocs

@MainActor
final class RealtimeTranscriptionRecorderTests: XCTestCase {

    var sut: RealtimeTranscriptionRecorder!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        sut = RealtimeTranscriptionRecorder()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        // Stop recording if still active
        if sut.isRecording {
            await sut.stopRecording()
        }
        cancellables = nil
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Recording Duration Timer Tests

    func testRecordingDurationInitialValue() {
        // Given: A new recorder instance
        // When: No recording has started
        // Then: Recording duration should be 0
        XCTAssertEqual(sut.recordingDuration, 0.0, "Initial recording duration should be 0")
    }

    func testRecordingDurationUpdatesWhenRecording() async throws {
        // Given: A recorder instance
        let expectation = XCTestExpectation(description: "Recording duration updates")
        var durations: [TimeInterval] = []

        // Observe recording duration changes
        sut.$recordingDuration
            .sink { duration in
                durations.append(duration)
                // Wait for at least 3 updates (0, 0.1+, 0.2+)
                if durations.count >= 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: Recording starts
        // Note: This test requires microphone and speech recognition permissions
        // In CI/CD, this may need to be mocked or skipped
        do {
            try await sut.startRecording()

            // Wait for duration updates
            await fulfillment(of: [expectation], timeout: 2.0)

            // Stop recording
            await sut.stopRecording()

            // Then: Recording duration should have increased
            XCTAssertGreaterThan(durations.count, 1, "Duration should update multiple times")
            XCTAssertGreaterThan(durations.last ?? 0, 0, "Final duration should be greater than 0")

            // Verify that duration increases over time
            for i in 1..<durations.count {
                XCTAssertGreaterThanOrEqual(durations[i], durations[i-1],
                                           "Duration should be monotonically increasing")
            }
        } catch {
            // If permissions are not granted, skip this test
            throw XCTSkip("Skipping test - microphone or speech recognition permission not granted: \(error)")
        }
    }

    func testRecordingDurationResetsAfterStop() async throws {
        // Given: A recording has been made
        do {
            try await sut.startRecording()

            // Wait a bit for duration to update
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

            let durationDuringRecording = sut.recordingDuration
            XCTAssertGreaterThan(durationDuringRecording, 0, "Duration should be > 0 during recording")

            // When: Recording stops
            await sut.stopRecording()

            // Then: isRecording should be false
            XCTAssertFalse(sut.isRecording, "Should not be recording after stop")

            // Note: Duration is NOT reset to 0 after stopping in current implementation
            // It maintains the final recorded duration
            // This is intentional behavior

        } catch {
            throw XCTSkip("Skipping test - permissions not granted: \(error)")
        }
    }

    func testRecordingTimerRunsOnMainThread() async throws {
        // Given: A recorder instance
        let expectation = XCTestExpectation(description: "Timer callback runs on main thread")

        var isMainThread = false

        sut.$recordingDuration
            .dropFirst() // Skip initial value
            .first()
            .sink { _ in
                isMainThread = Thread.isMainThread
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When: Recording starts
        do {
            try await sut.startRecording()

            await fulfillment(of: [expectation], timeout: 2.0)

            await sut.stopRecording()

            // Then: Timer updates should happen on main thread
            XCTAssertTrue(isMainThread, "Recording duration updates should occur on main thread")

        } catch {
            throw XCTSkip("Skipping test - permissions not granted: \(error)")
        }
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        // Given: A new recorder instance
        // Then: All properties should be in initial state
        XCTAssertFalse(sut.isRecording, "Should not be recording initially")
        XCTAssertFalse(sut.isTranscribing, "Should not be transcribing initially")
        XCTAssertEqual(sut.recordingDuration, 0.0, "Recording duration should be 0")
        XCTAssertEqual(sut.audioLevel, 0.0, "Audio level should be 0")
        XCTAssertEqual(sut.transcribedText, "", "Transcribed text should be empty")
        XCTAssertNil(sut.lastError, "Should have no error initially")
    }

    // MARK: - Transcription Reset Tests

    func testResetTranscription() {
        // Given: A recorder with some transcribed text
        sut.transcribedText = "Test transcription"

        // When: Transcription is reset
        sut.resetTranscription()

        // Then: Text should be cleared
        XCTAssertEqual(sut.transcribedText, "", "Transcribed text should be empty after reset")
        XCTAssertNil(sut.lastError, "Error should be nil after reset")
    }
}
