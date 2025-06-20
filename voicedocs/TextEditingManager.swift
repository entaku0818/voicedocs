//
//  TextEditingManager.swift
//  voicedocs
//
//  Created by Claude on 2025/6/18.
//

import SwiftUI
import Foundation

class TextEditingManager: ObservableObject {
    @Published var text: String = ""
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private let maxUndoSteps = 50
    private var isPerformingUndoRedo = false
    
    init(initialText: String = "") {
        self.text = initialText
        self.undoStack = [initialText]
    }
    
    // MARK: - Text Management
    
    func updateText(_ newText: String, recordUndo: Bool = true) {
        guard !isPerformingUndoRedo else {
            text = newText
            updateUndoRedoState()
            return
        }
        
        if recordUndo && newText != text {
            saveStateForUndo()
        }
        
        text = newText
        
        // テキストが変更されたらredoスタックをクリア
        if recordUndo {
            redoStack.removeAll()
        }
        
        updateUndoRedoState()
    }
    
    // MARK: - Undo/Redo Operations
    
    func undo() {
        guard canUndo, undoStack.count > 1 else { return }
        
        isPerformingUndoRedo = true
        
        // 現在のテキストをredoスタックに保存
        redoStack.append(text)
        
        // undoスタックから前の状態を取得
        undoStack.removeLast()
        let previousText = undoStack.last ?? ""
        
        text = previousText
        updateUndoRedoState()
        
        isPerformingUndoRedo = false
    }
    
    func redo() {
        guard canRedo, !redoStack.isEmpty else { return }
        
        isPerformingUndoRedo = true
        
        // redoスタックから次の状態を取得
        let nextText = redoStack.removeLast()
        
        // 現在のテキストをundoスタックに保存
        undoStack.append(text)
        
        text = nextText
        updateUndoRedoState()
        
        isPerformingUndoRedo = false
    }
    
    // MARK: - Private Methods
    
    private func saveStateForUndo() {
        undoStack.append(text)
        
        // スタックサイズを制限
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
    }
    
    private func updateUndoRedoState() {
        canUndo = undoStack.count > 1
        canRedo = !redoStack.isEmpty
    }
    
    // MARK: - Utility Methods
    
    func clearHistory() {
        undoStack = [text]
        redoStack.removeAll()
        updateUndoRedoState()
    }
    
    func getUndoStackSize() -> Int {
        return undoStack.count
    }
    
    func getRedoStackSize() -> Int {
        return redoStack.count
    }
}

// MARK: - Text Editing Operations

extension TextEditingManager {
    
    // 検索・置換操作
    func replaceText(searchText: String, replaceText: String, caseSensitive: Bool = false, wholeWordsOnly: Bool = false) -> Int {
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var newText = text
        var replacements = 0
        
        // すべての出現箇所を見つける
        let ranges = findOccurrences(of: searchText, in: text, options: options, wholeWordsOnly: wholeWordsOnly)
        
        // 後ろから置換して位置がずれないようにする
        for range in ranges.reversed() {
            let nsString = newText as NSString
            newText = nsString.replacingCharacters(in: range, with: replaceText)
            replacements += 1
        }
        
        if replacements > 0 {
            updateText(newText)
        }
        
        return replacements
    }
    
    // 指定位置のテキストを置換
    func replaceTextAtRange(_ range: NSRange, with replacement: String) {
        let nsString = text as NSString
        let newText = nsString.replacingCharacters(in: range, with: replacement)
        updateText(newText)
    }
    
    // テキストを追加
    func appendText(_ additionalText: String) {
        updateText(text + additionalText)
    }
    
    // テキストを挿入
    func insertText(_ insertText: String, at position: Int) {
        let index = text.index(text.startIndex, offsetBy: min(position, text.count))
        let newText = String(text.prefix(upTo: index)) + insertText + String(text.suffix(from: index))
        updateText(newText)
    }
    
    // MARK: - Search Helpers
    
    private func findOccurrences(of searchString: String, in text: String, options: String.CompareOptions, wholeWordsOnly: Bool = false) -> [NSRange] {
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
}