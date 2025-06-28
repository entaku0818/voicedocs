import SwiftUI

struct TitleEditModal: View {
    let title: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var editedTitle: String
    
    init(title: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
        self._editedTitle = State(initialValue: title)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("タイトルを編集")
                    .font(.headline)
                    .padding(.top)
                
                TextField("タイトルを入力", text: $editedTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("タイトル編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave(editedTitle)
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}