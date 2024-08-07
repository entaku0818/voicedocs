//
//  VoiceMemoListView.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation
import SwiftUI

struct VoiceMemoListView: View {
    private var voiceMemoController: VoiceMemoControllerProtocol
    @State private var voiceMemos: [VoiceMemo] = []
    private let admobKey: String

    init(voiceMemoController: VoiceMemoControllerProtocol,admobKey:String) {
        self.voiceMemoController = voiceMemoController
        self._voiceMemos = State(initialValue: voiceMemoController.fetchVoiceMemos())
        self.admobKey = admobKey
    }

    var body: some View {
        NavigationView {
            VStack {
                List(voiceMemos, id: \.id) { memo in
                    NavigationLink(destination: VoiceMemoDetailView(memo: memo, admobKey: admobKey)) {
                        VStack(alignment: .leading) {
                            Text(memo.title)
                                .font(.headline)
                            Text(memo.date, style: .relative)
                        }
                    }
                }
                .navigationTitle("Voice Memos")

                NavigationLink(destination: ContentView()) {
                    Text("Record New Memo")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding()
                }
            }
            .onAppear {
                self.voiceMemos = voiceMemoController.fetchVoiceMemos()
            }
        }
    }
}


#Preview {
    VoiceMemoListView(voiceMemoController: FakeVoiceMemoController(), admobKey: "")
}
