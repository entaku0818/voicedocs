//
//  VoiceMemoListView.swift
//  voicedocs
//
//  Created by 遠藤拓弥 on 2024/06/09.
//

import Foundation
import SwiftUI
import ComposableArchitecture

struct VoiceMemoListView: View {
    private var voiceMemoController: VoiceMemoControllerProtocol
    @State private var voiceMemos: [VoiceMemo] = []
    @State private var showingDeleteAlert = false
    @State private var memoToDelete: VoiceMemo?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .dateNewest
    @State private var showingSortOptions = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showingSearchAndSort = false
    @State private var isSearchActive = false
    @Environment(\.admobConfig) private var admobConfig

    // ファイルインポート関連
    @State private var showingFilePicker = false
    @State private var showingImportResult = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importResult: ImportResult?
    @State private var importError: String?
    @StateObject private var inputSourceManager = InputSourceManager()

    // インポート後の遷移用
    @State private var navigateToMemo: VoiceMemo?
    @State private var shouldNavigateToDetail = false

    // 長さ順ソート用のdurationキャッシュ
    @State private var durationCache: [UUID: TimeInterval] = [:]

    init(voiceMemoController: VoiceMemoControllerProtocol = VoiceMemoController.shared) {
        self.voiceMemoController = voiceMemoController
        self._voiceMemos = State(initialValue: voiceMemoController.fetchVoiceMemos())
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 検索とソートセクション
                if isSearchActive {
                    VStack(spacing: 12) {
                        // 検索バー
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("文字起こし結果を検索", text: $searchText)
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        // ソートオプション
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(SortOption.allCases, id: \.self) { option in
                                    Button(action: { sortOption = option }) {
                                        Text(option.displayName)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(sortOption == option ? Color.accentColor : Color(.systemGray5))
                                            .foregroundColor(sortOption == option ? .white : .primary)
                                            .cornerRadius(15)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .overlay(
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )
                }
                
                List {
                    if voiceMemos.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "mic.slash")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("文字起こし結果がありません")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("下のボタンで新しい録音を開始してください")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(sortedAndFilteredMemos, id: \.id) { memo in
                            NavigationLink(destination: VoiceMemoDetailView(
                                store: Store(
                                    initialState: VoiceMemoDetailFeature.State(memo: memo),
                                    reducer: { VoiceMemoDetailFeature() }
                                ),
                                admobKey: admobConfig.interstitialAdUnitID,
                                onMemoUpdated: { refreshMemos() }
                            )) {
                                VoiceMemoRow(memo: memo, voiceMemoController: voiceMemoController)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("共有") {
                                    shareMemo(memo)
                                }
                                .tint(.blue)
                                
                                Button("削除", role: .destructive) {
                                    memoToDelete = memo
                                    showingDeleteAlert = true
                                }
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                
                // バナー広告を下部に配置
                bannerAdSection()
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("文字起こし結果")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { 
                            withAnimation {
                                isSearchActive.toggle()
                                if !isSearchActive {
                                    searchText = ""
                                }
                            }
                        }) {
                            Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                        }
                    }
                }


                // アクションボタン
                HStack(spacing: 12) {
                    // 新しい録音ボタン
                    NavigationLink(destination: ContentView()) {
                        HStack {
                            Image(systemName: "mic.fill")
                            Text("録音")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    // ファイルからインポートボタン
                    Button(action: { showingFilePicker = true }) {
                        HStack {
                            Image(systemName: "doc.fill")
                            Text("ファイル")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .onAppear {
                refreshMemos()
                inputSourceManager.cleanupOldImports()
            }
            .alert("文字起こし結果を削除", isPresented: $showingDeleteAlert) {
                Button("削除", role: .destructive) {
                    if let memo = memoToDelete {
                        deleteMemo(memo)
                    }
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("この文字起こし結果を削除しますか？この操作は取り消せません。")
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showingFilePicker) {
                AudioFilePickerView(isPresented: $showingFilePicker) { url in
                    handleFileSelected(url: url)
                }
            }
            .background(
                // インポート後の詳細ビューへの遷移用NavigationLink
                NavigationLink(
                    destination: Group {
                        if let memo = navigateToMemo {
                            VoiceMemoDetailView(
                                store: Store(
                                    initialState: VoiceMemoDetailFeature.State(memo: memo),
                                    reducer: { VoiceMemoDetailFeature() }
                                ),
                                admobKey: admobConfig.interstitialAdUnitID,
                                onMemoUpdated: { refreshMemos() }
                            )
                        }
                    },
                    isActive: $shouldNavigateToDetail,
                    label: { EmptyView() }
                )
                .hidden()
            )
            .sheet(isPresented: $showingImportResult) {
                if let result = importResult {
                    ImportResultSheet(
                        result: result,
                        onTranscribe: {
                            showingImportResult = false
                            // メモを作成し、詳細ビュー（文字起こし処理画面）へ遷移
                            createMemoFromImport(result: result)
                        },
                        onCancel: {
                            showingImportResult = false
                            if let url = importResult?.processedURL {
                                inputSourceManager.deleteImportedFile(at: url)
                            }
                            importResult = nil
                        }
                    )
                }
            }
            .overlay {
                if isImporting {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ImportProgressView(
                        progress: importProgress,
                        fileName: "インポート中..."
                    )
                }
            }
            .alert("インポートエラー", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - File Import Handling

    private func handleFileSelected(url: URL) {
        isImporting = true
        importProgress = 0

        Task {
            do {
                let result = try await inputSourceManager.importAudioFile(from: url)
                await MainActor.run {
                    isImporting = false
                    importResult = result
                    showingImportResult = true
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func createMemoFromImport(result: ImportResult) {
        Task {
            // VoiceMemoを作成
            let title = "📁 " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)

            do {
                // 音声ファイルをVoiceRecordingsディレクトリにコピー
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let voiceRecordingsPath = documentsPath.appendingPathComponent("VoiceRecordings")

                // ディレクトリが存在しない場合は作成
                if !FileManager.default.fileExists(atPath: voiceRecordingsPath.path) {
                    try FileManager.default.createDirectory(at: voiceRecordingsPath, withIntermediateDirectories: true)
                }

                // メモIDを先に生成（ファイル名に使用）
                let memoId = UUID()
                let audioFileName = "recording-\(memoId.uuidString).m4a"
                let destURL = voiceRecordingsPath.appendingPathComponent(audioFileName)

                try FileManager.default.copyItem(at: result.processedURL, to: destURL)

                // メモを保存（VoiceMemoControllerのメソッドを使用）
                // voiceFilePathは不要（IDから自動解決される）
                voiceMemoController.saveVoiceMemo(id: memoId, title: title, text: "", filePath: "")

                // セグメントを追加（音声ファイルの情報）
                let segment = AudioSegment(
                    id: UUID(),
                    filePath: audioFileName,
                    startTime: 0,
                    duration: result.duration ?? 0,
                    createdAt: Date()
                )
                _ = voiceMemoController.addSegmentToMemo(memoId: memoId, segment: segment)

                await MainActor.run {
                    refreshMemos()
                    // インポートした一時ファイルを削除
                    inputSourceManager.deleteImportedFile(at: result.processedURL)
                    importResult = nil
                    // インポートしたメモの詳細ビューへ遷移
                    if let createdMemo = voiceMemoController.fetchVoiceMemo(id: memoId) {
                        navigateToMemo = createdMemo
                        shouldNavigateToDetail = true
                    }
                }
            } catch {
                await MainActor.run {
                    importError = "メモの作成に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private var sortedAndFilteredMemos: [VoiceMemo] {
        let filtered = searchText.isEmpty ? voiceMemos : voiceMemos.filter { memo in
            memo.title.localizedCaseInsensitiveContains(searchText) ||
            memo.text.localizedCaseInsensitiveContains(searchText)
        }
        
        return filtered.sorted { (memo1: VoiceMemo, memo2: VoiceMemo) in
            switch sortOption {
            case .dateNewest:
                return memo1.date > memo2.date
            case .dateOldest:
                return memo1.date < memo2.date
            case .titleAZ:
                return memo1.title.localizedCompare(memo2.title) == .orderedAscending
            case .titleZA:
                return memo1.title.localizedCompare(memo2.title) == .orderedDescending
            case .durationLongest:
                let duration1 = durationCache[memo1.id] ?? memo1.totalDuration
                let duration2 = durationCache[memo2.id] ?? memo2.totalDuration
                if duration1 == duration2 {
                    return memo1.date > memo2.date // 同じ長さなら日付でソート
                }
                return duration1 > duration2
            case .durationShortest:
                let duration1 = durationCache[memo1.id] ?? memo1.totalDuration
                let duration2 = durationCache[memo2.id] ?? memo2.totalDuration
                if duration1 == duration2 {
                    return memo1.date < memo2.date // 同じ長さなら日付でソート
                }
                return duration1 < duration2
            }
        }
    }
    
    private func refreshMemos() {
        voiceMemos = voiceMemoController.fetchVoiceMemos()
        // 長さ順ソート用にdurationをキャッシュ
        loadDurationCache()
    }

    private func loadDurationCache() {
        guard let controller = voiceMemoController as? VoiceMemoController else { return }
        Task {
            var newCache: [UUID: TimeInterval] = [:]
            for memo in voiceMemos {
                // まずセグメントからの計算値を使用
                let segmentDuration = memo.totalDuration
                if segmentDuration > 0 {
                    newCache[memo.id] = segmentDuration
                } else {
                    // セグメントにdurationがない場合は非同期で取得
                    if let duration = await controller.getAudioDurationById(memo.id) {
                        newCache[memo.id] = duration
                    }
                }
            }
            await MainActor.run {
                durationCache = newCache
            }
        }
    }
    
    private func deleteMemo(_ memo: VoiceMemo) {
        Task {
            if await voiceMemoController.deleteVoiceMemo(id: memo.id) {
                await MainActor.run {
                    refreshMemos()
                }
            }
        }
    }
    
    private func shareMemo(_ memo: VoiceMemo) {
        var items: [Any] = []
        
        // テキスト内容
        let textContent = """
        タイトル: \(memo.title)
        作成日時: \(formatDate(memo.date))
        
        文字起こし結果:
        \(memo.text)
        """
        items.append(textContent)
        
        shareItems = items
        showingShareSheet = true
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func bannerAdSection() -> some View {
        VStack {
            Divider()
            
            BannerAdView(adUnitID: admobConfig.bannerAdUnitID)
                .frame(height: 50)
                .background(Color(.systemGray6))
        }
    }
}

struct VoiceMemoRow: View {
    let memo: VoiceMemo
    let voiceMemoController: VoiceMemoControllerProtocol
    @State private var duration: TimeInterval?
    @State private var fileSize: Int64?
    
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
                if let duration = duration {
                    Label(formatDuration(duration), systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Label("--:--", systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let fileSize = fileSize {
                    Label(formatFileSize(fileSize), systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Label("--", systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadFileInfo()
        }
    }
    
    private func loadFileInfo() {
        Task {
            // VoiceMemoControllerにUUIDベースのメソッドがあることを確認
            if let controller = voiceMemoController as? VoiceMemoController {
                let asyncDuration = await controller.getAudioDurationById(memo.id)
                let asyncFileSize = await controller.getFileSizeById(memo.id)
                
                await MainActor.run {
                    self.duration = asyncDuration
                    self.fileSize = asyncFileSize
                }
            }
        }
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

enum SortOption: String, CaseIterable {
    case dateNewest = "dateNewest"
    case dateOldest = "dateOldest"
    case titleAZ = "titleAZ"
    case titleZA = "titleZA"
    case durationLongest = "durationLongest"
    case durationShortest = "durationShortest"
    
    var displayName: String {
        switch self {
        case .dateNewest:
            return "日付（新しい順）"
        case .dateOldest:
            return "日付（古い順）"
        case .titleAZ:
            return "タイトル（A-Z）"
        case .titleZA:
            return "タイトル（Z-A）"
        case .durationLongest:
            return "長さ（長い順）"
        case .durationShortest:
            return "長さ（短い順）"
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 更新処理は不要
    }
}


#Preview {
    VoiceMemoListView(voiceMemoController: FakeVoiceMemoController())
}
