//
//  voicedocsTests.swift
//  voicedocsTests
//
//  Created by 遠藤拓弥 on 2024/06/01.
//

import XCTest
import AVFoundation
@testable import voicedocs

final class voicedocsTests: XCTestCase {
    var audioRecorder: AudioRecorder!

    override func setUpWithError() throws {
        audioRecorder = AudioRecorder()
    }

    override func tearDownWithError() throws {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        }
        audioRecorder = nil
    }

    func testAudioRecorderInitialization() throws {
        XCTAssertNotNil(audioRecorder)
        XCTAssertFalse(audioRecorder.isRecording)
        XCTAssertEqual(audioRecorder.recordingDuration, 0)
        XCTAssertEqual(audioRecorder.audioLevel, 0.0)
        XCTAssertEqual(audioRecorder.recordingQuality, .high)
    }
    
    func testRecordingQualitySettings() throws {
        let standardQuality = RecordingQuality.standard
        let highQuality = RecordingQuality.high
        
        XCTAssertEqual(standardQuality.displayName, "標準品質")
        XCTAssertEqual(highQuality.displayName, "高品質")
        
        let standardSettings = standardQuality.settings
        let highSettings = highQuality.settings
        
        XCTAssertNotNil(standardSettings[AVSampleRateKey])
        XCTAssertNotNil(highSettings[AVSampleRateKey])
        
        let standardSampleRate = standardSettings[AVSampleRateKey] as? Int
        let highSampleRate = highSettings[AVSampleRateKey] as? Int
    }
    
    func testRecordingQualityChange() throws {
        XCTAssertEqual(audioRecorder.recordingQuality, .high)
        
        audioRecorder.setRecordingQuality(.standard)
        XCTAssertEqual(audioRecorder.recordingQuality, .standard)
        
        audioRecorder.setRecordingQuality(.high)
        XCTAssertEqual(audioRecorder.recordingQuality, .high)
    }
    
    func testRecordingQualityAllCases() throws {
        let allQualities = RecordingQuality.allCases
        XCTAssertEqual(allQualities.count, 2)
        XCTAssertTrue(allQualities.contains(.standard))
        XCTAssertTrue(allQualities.contains(.high))
    }

}
