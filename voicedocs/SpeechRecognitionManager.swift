//
//  SpeechRecognitionManager.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/01.
//

import Foundation
import Speech
import AVFoundation
import Combine
import AVFoundation
import Speech
import Combine

class SpeechRecognitionManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?

    @Published var transcribedText: String = ""
    @Published var audioLevel: Float = 0.0 // 音の大きさを表すプロパティ

    func startRecording() async throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object") }
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.transcribedText = result.bestTranscription.formattedString
            }

            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        audioFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            self.recognitionRequest?.append(buffer)
            try? self.audioFile?.write(from: buffer)

            self.updateAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopRecording() -> URL? {
        audioEngine.stop()
        recognitionRequest?.endAudio()

        let fileURL = audioFile?.url
        audioFile = nil
        return fileURL
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0,
                                           to: Int(buffer.frameLength),
                                           by: buffer.stride).map { channelDataValue[$0] }
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)
        DispatchQueue.main.async {
            self.audioLevel = avgPower
        }
    }
}
