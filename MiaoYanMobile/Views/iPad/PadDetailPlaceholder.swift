import SwiftUI

/// Detail-column empty state for the iPad split layout, shown until the
/// user picks a note.
struct PadDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.page")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(MobileTheme.secondaryInk)
            Text("Select a note")
                .font(MobileTheme.editorialFont(.title3, weight: .semibold))
                .foregroundStyle(MobileTheme.ink)
            Text("Pick a note from the list to start reading.")
                .font(MobileTheme.font(.subheadline))
                .foregroundStyle(MobileTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(MobileTheme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mobilePaperBackground()
    }
}
