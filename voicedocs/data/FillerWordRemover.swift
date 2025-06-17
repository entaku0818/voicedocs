//
//  FillerWordRemover.swift
//  voicedocs
//
//  Created by Claude on 2025/6/16.
//

import Foundation

enum FillerWordLanguage: String, CaseIterable {
    case japanese = "ja"
    case english = "en"
    
    var displayName: String {
        switch self {
        case .japanese:
            return "日本語"
        case .english:
            return "English"
        }
    }
}

struct FillerWordPattern {
    let word: String
    let language: FillerWordLanguage
    let isRegex: Bool
    
    init(word: String, language: FillerWordLanguage, isRegex: Bool = false) {
        self.word = word
        self.language = language
        self.isRegex = isRegex
    }
}

struct FillerWordRemovalResult {
    let originalText: String
    let cleanedText: String
    let removedWords: [String]
    let removedCount: Int
    
    var hasChanges: Bool {
        return removedCount > 0
    }
    
    var reductionPercentage: Double {
        guard originalText.count > 0 else { return 0.0 }
        let reduction = Double(originalText.count - cleanedText.count) / Double(originalText.count)
        return reduction * 100.0
    }
}

class FillerWordRemover {
    static let shared = FillerWordRemover()
    
    private let builtInPatterns: [FillerWordPattern] = [
        // 日本語フィラーワード
        FillerWordPattern(word: "えー+", language: .japanese, isRegex: true),
        FillerWordPattern(word: "あー+", language: .japanese, isRegex: true),
        FillerWordPattern(word: "うー+", language: .japanese, isRegex: true),
        FillerWordPattern(word: "えっと", language: .japanese),
        FillerWordPattern(word: "あの", language: .japanese),
        FillerWordPattern(word: "その", language: .japanese),
        FillerWordPattern(word: "なんか", language: .japanese),
        FillerWordPattern(word: "まあ", language: .japanese),
        FillerWordPattern(word: "ちょっと", language: .japanese),
        FillerWordPattern(word: "はい", language: .japanese),
        FillerWordPattern(word: "そうですね", language: .japanese),
        FillerWordPattern(word: "そうですね。", language: .japanese),
        
        // 英語フィラーワード
        FillerWordPattern(word: "uh+", language: .english, isRegex: true),
        FillerWordPattern(word: "um+", language: .english, isRegex: true),
        FillerWordPattern(word: "ah+", language: .english, isRegex: true),
        FillerWordPattern(word: "well", language: .english),
        FillerWordPattern(word: "you know", language: .english),
        FillerWordPattern(word: "like", language: .english),
        FillerWordPattern(word: "actually", language: .english),
        FillerWordPattern(word: "basically", language: .english),
        FillerWordPattern(word: "literally", language: .english),
        FillerWordPattern(word: "I mean", language: .english),
        FillerWordPattern(word: "right", language: .english),
        FillerWordPattern(word: "okay", language: .english),
        FillerWordPattern(word: "so", language: .english)
    ]
    
    private var customPatterns: [FillerWordPattern] = []
    
    private init() {}
    
    // MARK: - Public Methods
    
    func removeFillerWords(from text: String, languages: [FillerWordLanguage] = FillerWordLanguage.allCases) -> FillerWordRemovalResult {
        let applicablePatterns = getApplicablePatterns(for: languages)
        var cleanedText = text
        var removedWords: [String] = []
        
        for pattern in applicablePatterns {
            let (newText, removed) = removePattern(pattern, from: cleanedText)
            cleanedText = newText
            removedWords.append(contentsOf: removed)
        }
        
        // 複数の空白を単一の空白に置換
        cleanedText = cleanedText.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        
        return FillerWordRemovalResult(
            originalText: text,
            cleanedText: cleanedText,
            removedWords: removedWords,
            removedCount: removedWords.count
        )
    }
    
    func detectFillerWords(in text: String, languages: [FillerWordLanguage] = FillerWordLanguage.allCases) -> [String] {
        let applicablePatterns = getApplicablePatterns(for: languages)
        var detectedWords: Set<String> = []
        
        for pattern in applicablePatterns {
            let matches = findMatches(for: pattern, in: text)
            detectedWords.formUnion(matches)
        }
        
        return Array(detectedWords).sorted()
    }
    
    func addCustomPattern(_ pattern: FillerWordPattern) {
        customPatterns.append(pattern)
    }
    
    func removeCustomPattern(_ pattern: FillerWordPattern) {
        customPatterns.removeAll { $0.word == pattern.word && $0.language == pattern.language }
    }
    
    func getCustomPatterns() -> [FillerWordPattern] {
        return customPatterns
    }
    
    func getBuiltInPatterns(for language: FillerWordLanguage? = nil) -> [FillerWordPattern] {
        if let language = language {
            return builtInPatterns.filter { $0.language == language }
        }
        return builtInPatterns
    }
    
    // MARK: - Private Methods
    
    private func getApplicablePatterns(for languages: [FillerWordLanguage]) -> [FillerWordPattern] {
        let builtIn = builtInPatterns.filter { languages.contains($0.language) }
        let custom = customPatterns.filter { languages.contains($0.language) }
        return builtIn + custom
    }
    
    private func removePattern(_ pattern: FillerWordPattern, from text: String) -> (String, [String]) {
        if pattern.isRegex {
            return removeRegexPattern(pattern, from: text)
        } else {
            return removeSimplePattern(pattern, from: text)
        }
    }
    
    private func removeSimplePattern(_ pattern: FillerWordPattern, from text: String) -> (String, [String]) {
        var removedWords: [String] = []
        var workingText = text
        
        // 大文字小文字を区別しない検索
        let options: String.CompareOptions = [.caseInsensitive]
        
        while let range = workingText.range(of: pattern.word, options: options) {
            let removedWord = String(workingText[range])
            removedWords.append(removedWord)
            workingText.removeSubrange(range)
        }
        
        return (workingText, removedWords)
    }
    
    private func removeRegexPattern(_ pattern: FillerWordPattern, from text: String) -> (String, [String]) {
        do {
            let regex = try NSRegularExpression(pattern: pattern.word, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = regex.matches(in: text, options: [], range: range)
            
            var removedWords: [String] = []
            var result = text
            
            // 後ろから削除して範囲がずれないようにする
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    let removedWord = String(text[range])
                    removedWords.append(removedWord)
                    result.removeSubrange(range)
                }
            }
            
            return (result, removedWords.reversed())
        } catch {
            print("Regex error: \(error)")
            return (text, [])
        }
    }
    
    private func findMatches(for pattern: FillerWordPattern, in text: String) -> [String] {
        if pattern.isRegex {
            return findRegexMatches(pattern, in: text)
        } else {
            return findSimpleMatches(pattern, in: text)
        }
    }
    
    private func findSimpleMatches(_ pattern: FillerWordPattern, in text: String) -> [String] {
        var matches: [String] = []
        var searchRange = text.startIndex..<text.endIndex
        
        while let range = text.range(of: pattern.word, options: [.caseInsensitive], range: searchRange) {
            matches.append(String(text[range]))
            searchRange = range.upperBound..<text.endIndex
        }
        
        return matches
    }
    
    private func findRegexMatches(_ pattern: FillerWordPattern, in text: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern.word, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = regex.matches(in: text, options: [], range: range)
            
            return matches.compactMap { match in
                if let range = Range(match.range, in: text) {
                    return String(text[range])
                }
                return nil
            }
        } catch {
            print("Regex error: \(error)")
            return []
        }
    }
}