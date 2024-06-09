//
//  VoiceMemoDetailView.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation
import SwiftUI

struct VoiceMemoDetailView: View {
    var memo: VoiceMemo

    var body: some View {
        VStack(alignment: .leading) {
            Text(memo.title)
                .font(.largeTitle)
                .padding()

            Text(memo.text)
                .padding()

            Spacer()
        }
        .navigationTitle("Memo Details")
        .padding()
    }
}

#Preview {
    VoiceMemoDetailView(memo: VoiceMemo(id: UUID(), title: "Sample Memo", text: "This is a sample memo.", date: Date(), filePath: "/path/to/file"))
}
