//
//  Logger.swift
//  voicedocs
//
//  Created by Assistant on 2024/12/22.
//

import Foundation
import os.log

/// アプリ全体で使用するロガー
struct AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.voicedocs"
    
    /// 録音関連のログ
    static let recording = Logger(subsystem: subsystem, category: "Recording")
    
    /// 音声認識関連のログ
    static let speechRecognition = Logger(subsystem: subsystem, category: "SpeechRecognition")
    
    /// ファイル操作関連のログ
    static let fileOperation = Logger(subsystem: subsystem, category: "FileOperation")
    
    /// UI関連のログ
    static let ui = Logger(subsystem: subsystem, category: "UI")
    
    /// データ永続化関連のログ
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    
    /// 再生関連のログ
    static let playback = Logger(subsystem: subsystem, category: "Playback")
}

