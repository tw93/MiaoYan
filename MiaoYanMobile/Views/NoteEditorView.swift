import SwiftUI

struct NoteEditorView: View {
    let note: NoteFile
    @Binding var content: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $content)
            .font(.system(size: 16, design: .monospaced))
            .focused($isFocused)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onAppear {
                isFocused = true
            }
    }
}
