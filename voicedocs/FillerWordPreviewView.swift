//
//  FillerWordPreviewView.swift
//  voicedocs
//
//  Created by Claude on 2025/6/16.
//

import SwiftUI

struct FillerWordPreviewView: View {
    let result: FillerWordRemovalResult?
    let onApply: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result = result {
                        // 統計情報
                        VStack(alignment: .leading, spacing: 8) {
                            Text("除去統計")
                                .font(.headline)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("除去される単語数")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(result.removedCount)個")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text("文字数削減率")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", result.reductionPercentage))%")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                        // 除去される単語のリスト
                        if !result.removedWords.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("除去される単語")
                                    .font(.headline)
                                
                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 80))
                                ], spacing: 8) {
                                    ForEach(Array(Set(result.removedWords)).sorted(), id: \.self) { word in
                                        Text(word)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.1))
                                            .foregroundColor(.red)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                        
                        // 変更前後の比較
                        VStack(alignment: .leading, spacing: 8) {
                            Text("変更前後の比較")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                // 変更前
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("変更前")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    
                                    Text(result.originalText)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                        )
                                }
                                
                                // 変更後
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("変更後")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    
                                    Text(result.cleanedText)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        
                        if !result.hasChanges {
                            VStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.green)
                                
                                Text("フィラーワードは見つかりませんでした")
                                    .font(.headline)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                    } else {
                        Text("プレビューを読み込めませんでした")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("フィラーワード除去プレビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("適用") {
                        onApply()
                    }
                    .disabled(result?.hasChanges != true)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}