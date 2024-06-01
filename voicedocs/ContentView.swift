//
//  ContentView.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/01.
//

import SwiftUI


struct ContentView: View {
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()

    var body: some View {
        VStack {
            Text(speechRecognitionManager.transcribedText)
                .padding()

            HStack {
                Button(action: {
                    do {
                        try speechRecognitionManager.startRecording()
                    } catch {
                        print("Failed to start recording: \(error)")
                    }
                }) {
                    Text("Start Recording")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button(action: {
                    speechRecognitionManager.stopRecording()
                }) {
                    Text("Stop Recording")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
    }
}


#Preview {
    ContentView()
}
