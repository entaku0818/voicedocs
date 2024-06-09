//
//  File.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation
import SwiftUI

struct VoiceMemoListView: View {
    @State private var voiceMemos: [VoiceMemo] = []

    init() {
        self.voiceMemos = VoiceMemoController.shared.fetchVoiceMemos()
    }

    var body: some View {
        List(voiceMemos, id: \.id) { memo in
            VStack(alignment: .leading) {
                Text(memo.title)
                    .font(.headline)
                Text(memo.text)
                Text(memo.date, style: .date)
            }
        }
        .navigationTitle("Voice Memos")
        .onAppear {
            self.voiceMemos = VoiceMemoController.shared.fetchVoiceMemos()
        }
    }
}

#Preview {
    VoiceMemoListView()
}
