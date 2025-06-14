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
    @State private var showingDeleteAlert = false
    @State private var memoToDelete: VoiceMemo?
    @State private var searchText = ""
    private let admobKey: String

    init(voiceMemoController: VoiceMemoControllerProtocol,admobKey:String) {
        self.voiceMemoController = voiceMemoController
        self._voiceMemos = State(initialValue: voiceMemoController.fetchVoiceMemos())
        self.admobKey = admobKey
    }

    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(filteredMemos, id: \.id) { memo in
                        NavigationLink(destination: VoiceMemoDetailView(
                            memo: memo, 
                            admobKey: admobKey,
                            onMemoUpdated: { refreshMemos() }
                        )) {
                            VoiceMemoRow(memo: memo, voiceMemoController: voiceMemoController)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("削除", role: .destructive) {
                                memoToDelete = memo
                                showingDeleteAlert = true
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "メモを検索")
                .navigationTitle("音声メモ")

                NavigationLink(destination: ContentView()) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("新しい録音")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding()
                }
            }
            .onAppear {
                refreshMemos()
            }
            .alert("メモを削除", isPresented: $showingDeleteAlert) {
                Button("削除", role: .destructive) {
                    if let memo = memoToDelete {
                        deleteMemo(memo)
                    }
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("このメモを削除しますか？この操作は取り消せません。")
            }
        }
    }
    
    private var filteredMemos: [VoiceMemo] {
        if searchText.isEmpty {
            return voiceMemos
        } else {
            return voiceMemos.filter { memo in
                memo.title.localizedCaseInsensitiveContains(searchText) ||
                memo.text.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private func refreshMemos() {
        voiceMemos = voiceMemoController.fetchVoiceMemos()
    }
    
    private func deleteMemo(_ memo: VoiceMemo) {
        if voiceMemoController.deleteVoiceMemo(id: memo.id) {
            refreshMemos()
        }
    }
}

struct VoiceMemoRow: View {
    let memo: VoiceMemo
    let voiceMemoController: VoiceMemoControllerProtocol
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(memo.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(formatDate(memo.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !memo.text.isEmpty {
                Text(memo.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                if let duration = voiceMemoController.getAudioDuration(filePath: memo.filePath) {
                    Label(formatDuration(duration), systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let fileSize = voiceMemoController.getFileSize(filePath: memo.filePath) {
                    Label(formatFileSize(fileSize), systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}


#Preview {
    VoiceMemoListView(voiceMemoController: FakeVoiceMemoController(), admobKey: "")
}
