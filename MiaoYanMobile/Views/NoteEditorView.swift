import SwiftUI

struct NoteEditorView: View {
    let note: NoteFile
    @Binding var content: String
    let saveState: NoteSaveState
    let onDone: () -> Void
    @FocusState private var isFocused: Bool
    @State private var focusTask: Task<Void, Never>?

    /// Wait for the sheet present transition to settle before requesting
    /// keyboard focus. Triggering the keyboard during the transition makes
    /// SwiftUI co-schedule four heavy things in the same frame: sheet
    /// animation, TextEditor (UITextView) first init, content layout, and
    /// keyboard / IME spin-up. Splitting them shaves visible jank on first
    /// open of large notes.
    private static let focusDelay: Duration = .milliseconds(350)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.title)
                        .font(MobileTheme.editorialFont(.title2, weight: .semibold))
                        .foregroundStyle(MobileTheme.ink)
                        .lineLimit(2)
                    SaveStatusPill(state: saveState)
                }
                .padding(.horizontal, MobileTheme.pagePadding)
                .padding(.top, 18)
                .padding(.bottom, 14)

                Rectangle()
                    .fill(MobileTheme.hairline)
                    .frame(height: 1)

                TextEditor(text: $content)
                    .font(MobileTheme.editorialFont(size: 17))
                    .foregroundStyle(MobileTheme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(.horizontal, MobileTheme.pagePadding - 4)
                    .padding(.vertical, 12)
            }
            .background(MobileTheme.paper)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MobileTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                        .foregroundStyle(MobileTheme.accent)
                }
            }
        }
        .presentationBackground(MobileTheme.paper)
        .onAppear {
            focusTask?.cancel()
            focusTask = Task { @MainActor in
                do { try await Task.sleep(for: Self.focusDelay) } catch { return }
                guard !Task.isCancelled else { return }
                isFocused = true
            }
        }
        .onDisappear {
            focusTask?.cancel()
        }
    }
}

private struct SaveStatusPill: View {
    let state: NoteSaveState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .symbolEffect(.rotate, options: .repeating, isActive: isSaving)
            Text(state.label)
                .contentTransition(.opacity)
        }
        .font(MobileTheme.font(.caption, weight: .semibold))
        .foregroundStyle(color)
        .animation(.easeInOut(duration: 0.18), value: state)
    }

    private var iconName: String {
        switch state {
        case .saved: return "checkmark.circle.fill"
        case .unsaved: return "circle.dotted"
        case .saving: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.circle.fill"
        case .conflict: return "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }

    private var isSaving: Bool {
        if case .saving = state { return true }
        return false
    }

    private var color: Color {
        switch state {
        case .saved: return MobileTheme.accent
        case .unsaved, .saving: return MobileTheme.warmAccent
        case .failed, .conflict: return .red
        }
    }
}
