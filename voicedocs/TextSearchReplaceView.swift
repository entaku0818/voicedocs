//
//  TextSearchReplaceView.swift
//  voicedocs
//
//  Created by Claude on 2025/6/18.
//

import SwiftUI

struct SearchReplaceResult {
    let originalText: String
    let updatedText: String
    let replacements: Int
    let searchTerm: String
    let replaceTerm: String
}

struct TextSearchReplaceView: View {
    @Binding var text: String
    @State private var searchText: String = ""
    @State private var replaceText: String = ""
    @State private var caseSensitive: Bool = false
    @State private var wholeWordsOnly: Bool = false
    @State private var searchResults: [NSRange] = []
    @State private var currentResultIndex: Int = 0
    @State private var showingReplaceConfirmation: Bool = false
    @State private var pendingReplaceAll: Bool = false
    
    let onDismiss: () -> Void
    let onTextChanged: (String) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // 検索セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("検索")
                        .font(.headline)
                    
                    HStack {
                        TextField("検索テキスト", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: searchText) { _ in
                                performSearch()
                            }
                        
                        Button("検索") {
                            performSearch()
                        }
                        .disabled(searchText.isEmpty)
                    }
                    
                    // 検索結果表示
                    if !searchResults.isEmpty {
                        HStack {
                            Text("\(searchResults.count)件見つかりました")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if searchResults.count > 1 {
                                Button("前へ") {
                                    navigateToPrevious()
                                }
                                .disabled(currentResultIndex <= 0)
                                
                                Text("\(currentResultIndex + 1)/\(searchResults.count)")
                                    .font(.caption)
                                
                                Button("次へ") {
                                    navigateToNext()
                                }
                                .disabled(currentResultIndex >= searchResults.count - 1)
                            }
                        }
                    } else if !searchText.isEmpty {
                        Text("見つかりませんでした")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 置換セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("置換")
                        .font(.headline)
                    
                    TextField("置換後のテキスト", text: $replaceText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    HStack(spacing: 12) {
                        Button("置換") {
                            replaceCurrent()
                        }
                        .disabled(searchResults.isEmpty || searchText.isEmpty)
                        
                        Button("すべて置換") {
                            showingReplaceConfirmation = true
                            pendingReplaceAll = true
                        }
                        .disabled(searchResults.isEmpty || searchText.isEmpty)
                    }
                }
                
                // オプション
                VStack(alignment: .leading, spacing: 8) {
                    Text("オプション")
                        .font(.headline)
                    
                    Toggle("大文字小文字を区別", isOn: $caseSensitive)
                        .onChange(of: caseSensitive) { _ in
                            performSearch()
                        }
                    
                    Toggle("単語単位で検索", isOn: $wholeWordsOnly)
                        .onChange(of: wholeWordsOnly) { _ in
                            performSearch()
                        }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("検索・置換")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        onDismiss()
                    }
                }
            }
        }
        .alert("すべて置換", isPresented: $showingReplaceConfirmation) {
            Button("キャンセル", role: .cancel) {
                pendingReplaceAll = false
            }
            Button("置換", role: .destructive) {
                if pendingReplaceAll {
                    replaceAll()
                }
                pendingReplaceAll = false
            }
        } message: {
            Text("\(searchResults.count)箇所を「\(replaceText)」に置換しますか？")
        }
    }
    
    // MARK: - Search Functions
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            currentResultIndex = 0
            return
        }
        
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        searchResults = findOccurrences(of: searchText, in: text, options: options)
        currentResultIndex = 0
    }
    
    private func findOccurrences(of searchString: String, in text: String, options: String.CompareOptions) -> [NSRange] {
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.count)
        
        while searchRange.location < text.count {
            let foundRange = (text as NSString).range(of: searchString, options: options, range: searchRange)
            if foundRange.location == NSNotFound {
                break
            }
            
            // 単語単位検索のチェック
            if wholeWordsOnly {
                if isWholeWord(range: foundRange, in: text) {
                    results.append(foundRange)
                }
            } else {
                results.append(foundRange)
            }
            
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = text.count - searchRange.location
        }
        
        return results
    }
    
    private func isWholeWord(range: NSRange, in text: String) -> Bool {
        let nsString = text as NSString
        
        // 前の文字をチェック
        if range.location > 0 {
            let prevChar = nsString.character(at: range.location - 1)
            if CharacterSet.alphanumerics.contains(UnicodeScalar(prevChar)!) {
                return false
            }
        }
        
        // 後の文字をチェック
        let endLocation = range.location + range.length
        if endLocation < text.count {
            let nextChar = nsString.character(at: endLocation)
            if CharacterSet.alphanumerics.contains(UnicodeScalar(nextChar)!) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Navigation Functions
    
    private func navigateToNext() {
        if currentResultIndex < searchResults.count - 1 {
            currentResultIndex += 1
        }
    }
    
    private func navigateToPrevious() {
        if currentResultIndex > 0 {
            currentResultIndex -= 1
        }
    }
    
    // MARK: - Replace Functions
    
    private func replaceCurrent() {
        guard currentResultIndex < searchResults.count else { return }
        
        let range = searchResults[currentResultIndex]
        let nsString = text as NSString
        let newText = nsString.replacingCharacters(in: range, with: replaceText)
        
        text = newText
        onTextChanged(newText)
        
        // 検索結果を更新
        performSearch()
    }
    
    private func replaceAll() {
        guard !searchResults.isEmpty else { return }
        
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var newText = text
        var replacements = 0
        
        // 後ろから置換して位置がずれないようにする
        for range in searchResults.reversed() {
            let nsString = newText as NSString
            newText = nsString.replacingCharacters(in: range, with: replaceText)
            replacements += 1
        }
        
        text = newText
        onTextChanged(newText)
        
        // 検索結果をクリア
        searchResults = []
        currentResultIndex = 0
    }
}