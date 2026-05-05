import SwiftUI

struct NewNoteView: View {
    let folder: FolderItem
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Title", text: $title)
                    .font(MobileTheme.editorialFont(.title2, weight: .semibold))
                    .foregroundStyle(MobileTheme.ink)
                    .focused($titleFocused)
                    .padding(.horizontal, MobileTheme.pagePadding)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .submitLabel(.next)
                    .onSubmit { titleFocused = false }
                    .onChange(of: title) { errorMessage = nil }

                Rectangle()
                    .fill(MobileTheme.hairline)
                    .frame(height: 1)

                TextEditor(text: $content)
                    .font(MobileTheme.editorialFont(size: 17))
                    .foregroundStyle(MobileTheme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, MobileTheme.pagePadding - 4)
                    .padding(.vertical, 12)
                    .onChange(of: content) { errorMessage = nil }

                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            self.errorMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(MobileTheme.secondaryInk.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss error")
                    }
                    .font(MobileTheme.font(.footnote, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.10))
                    )
                    .padding(.horizontal, MobileTheme.pagePadding)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(MobileTheme.paper)
            .navigationTitle("New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MobileTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Haptics.tap()
                        dismiss()
                    }
                    .foregroundStyle(MobileTheme.secondaryInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(canSave == false || isSaving)
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? MobileTheme.accent : MobileTheme.secondaryInk)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: errorMessage)
        }
        .presentationBackground(MobileTheme.paper)
        .onAppear {
            titleFocused = true
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard !isSaving else { return }
        isSaving = true

        let snapshot = content
        let folder = folder
        Task {
            do {
                _ = try await NoteFileStore.createNote(title: trimmedTitle, content: snapshot, in: folder)
                Haptics.success()
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
                Haptics.error()
            }
        }
    }
}
