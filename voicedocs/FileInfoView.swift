import SwiftUI
import AVFoundation

struct FileInfoView: View {
    let memo: VoiceMemo
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // ファイル情報セクション
                VStack(alignment: .leading, spacing: 12) {
                    infoRow(label: "作成日時", value: formatDate(memo.date))
                    
                    Divider()
                    
                    let filePath = getFilePath(for: memo.id)
                    if let duration = getAudioDuration(filePath: filePath) {
                        infoRow(label: "録音時間", value: formatDuration(duration + memo.totalDuration))
                        Divider()
                    }
                    
                    if let fileSize = getFileSize(filePath: filePath) {
                        infoRow(label: "ファイルサイズ", value: formatFileSize(fileSize))
                        Divider()
                    }
                    
                    infoRow(label: "ファイルID", value: memo.id.uuidString)
                        .font(.system(.caption, design: .monospaced))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            .navigationTitle("詳細情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        onDismiss()
                    }
                }
            }
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func getFilePath(for memoId: UUID) -> String {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return ""
        }
        let voiceRecordingsPath = documentsDirectory.appendingPathComponent("VoiceRecordings")
        let filename = "recording-\(memoId.uuidString).m4a"
        return voiceRecordingsPath.appendingPathComponent(filename).path
    }
    
    private func getFileSize(filePath: String) -> Int64? {
        guard !filePath.isEmpty else { return nil }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    private func getAudioDuration(filePath: String) -> TimeInterval? {
        guard !filePath.isEmpty else { return nil }
        
        let fileURL = URL(fileURLWithPath: filePath)
        
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            return duration
        } catch {
            return nil
        }
    }
}