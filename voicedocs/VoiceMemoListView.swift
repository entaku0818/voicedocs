//
//  File.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation
import SwiftUI

struct VoiceMemoListView: View {
    private var voiceMemoController: VoiceMemoControllerProtocol
    @State private var voiceMemos: [VoiceMemo] = []

    init(voiceMemoController: VoiceMemoControllerProtocol) {
        self.voiceMemoController = voiceMemoController
        self._voiceMemos = State(initialValue: voiceMemoController.fetchVoiceMemos())
    }

    var body: some View {
        List(voiceMemos, id: \.id) { memo in
            VStack(alignment: .leading) {
                Text(memo.title)
                    .font(.headline)
                Text(memo.date, style: .relative)
            }
        }
        .navigationTitle("Voice Memos")
        .onAppear {
            self.voiceMemos = voiceMemoController.fetchVoiceMemos()
        }
    }
}

#Preview {
    VoiceMemoListView(voiceMemoController: FakeVoiceMemoController())
}
