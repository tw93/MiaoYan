import SwiftUI
import UIKit

/// Full-screen editing layer hosted inside NoteDetailView (replaced the old
/// modal sheet). Owns only the chrome — title header and save pill; the
/// text editing itself lives in MarkdownEditorView.
struct NoteEditView: View {
    let note: NoteFile
    @Binding var content: String
    let saveState: NoteSaveState
    let bodyFont: UIFont

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(note.title)
                    .font(MobileTheme.editorialFont(.title3, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
                    .lineLimit(1)
                SaveStatusPill(state: saveState)
            }
            .padding(.horizontal, MobileTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Rectangle()
                .fill(MobileTheme.hairline)
                .frame(height: 1)

            MarkdownEditorView(
                text: $content,
                bodyFont: bodyFont,
                noteFolderURL: note.url.deletingLastPathComponent()
            )
        }
        .background(MobileTheme.paper.ignoresSafeArea())
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
