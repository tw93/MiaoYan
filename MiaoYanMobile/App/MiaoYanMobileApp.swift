import SwiftUI
import UIKit

enum MobileTheme {
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.27)
    static let warmAccent = Color(red: 0.93, green: 0.48, blue: 0.28)
    static let paperUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            // Slightly lifted from pure black so eyes have something to anchor on.
            ? UIColor(red: 0.085, green: 0.090, blue: 0.085, alpha: 1)
            : UIColor(red: 0.975, green: 0.965, blue: 0.94, alpha: 1)
    }
    static let surfaceUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.135, green: 0.140, blue: 0.130, alpha: 1)
            : UIColor(red: 1.0, green: 0.992, blue: 0.972, alpha: 1)
    }
    static let paper = Color(
        uiColor: UIColor { traits in
            MobileTheme.paperUIColor.resolvedColor(with: traits)
        })
    static let surface = Color(
        uiColor: UIColor { traits in
            MobileTheme.surfaceUIColor.resolvedColor(with: traits)
        })
    static let elevatedSurface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.175, green: 0.180, blue: 0.165, alpha: 1)
                : UIColor(red: 1.0, green: 0.998, blue: 0.988, alpha: 1)
        })
    /// Reduced from previous (0.91, 0.90, 0.86) to (0.84, 0.82, 0.78);
    /// the original value was uncomfortably bright for long reading sessions.
    static let ink = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.84, green: 0.82, blue: 0.78, alpha: 1)
                : UIColor(red: 0.15, green: 0.14, blue: 0.12, alpha: 1)
        })
    static let secondaryInk = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.62, green: 0.61, blue: 0.56, alpha: 1)
                : UIColor(red: 0.42, green: 0.39, blue: 0.33, alpha: 1)
        })
    static let hairline = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.10)
                : UIColor.black.withAlphaComponent(0.07)
        })

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 17
    static let pagePadding: CGFloat = 18

    static func font(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(textStyle, design: .default, weight: weight)
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func editorialFont(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(textStyle, design: .serif, weight: weight)
    }

    static func editorialFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension View {
    func mobilePaperBackground() -> some View {
        background(MobileTheme.paper.ignoresSafeArea())
    }

    /// Card chrome tuned to play nicely with the iOS 26 glass tab bar.
    /// A large soft shadow under each card creates a heavy composition layer
    /// that the tab bar's blur has to repeatedly resample, which made tab
    /// switches feel sticky on real devices. We keep a much lighter shadow
    /// just for elevation cueing and rely on a hairline stroke + the warm
    /// surface vs. paper contrast for definition.
    func mobileCard() -> some View {
        padding(18)
            .background(
                RoundedRectangle(cornerRadius: MobileTheme.cardRadius, style: .continuous)
                    .fill(MobileTheme.surface)
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MobileTheme.cardRadius, style: .continuous)
                    .strokeBorder(MobileTheme.hairline, lineWidth: 0.5)
            )
    }

    /// Wraps `.glassEffect()` with a hairline stroke so the control still has a
    /// crisp silhouette when the system effect is muted (low power, transparency
    /// reduced, or unsupported on a given configuration).
    func mobileGlassControl() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(MobileTheme.hairline, lineWidth: 0.5)
            )
            .glassEffectIfAvailable()
    }

    /// iOS 26 introduced the Liquid Glass effect; on iOS 18-25 the underlying
    /// thinMaterial + hairline stroke that callers already set up acts as the
    /// fallback, so we just no-op the glass layer there.
    @ViewBuilder
    func glassEffectIfAvailable() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect()
        } else {
            self
        }
    }
}

@main
struct MiaoYanMobileApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var readerWebViewStore = ReaderWebViewStore()

    var body: some Scene {
        WindowGroup {
            FolderListView()
                .environmentObject(appState)
                .environmentObject(readerWebViewStore)
                .background(MobileTheme.paper.ignoresSafeArea())
                .task {
                    // Pre-warm the haptic engine so the user's first
                    // tap (refresh button, new-note, etc.) is instant
                    // instead of paying the ~50-100ms cold start.
                    Haptics.warmUp()
                    // Pre-warm the soft keyboard subsystem so the user's
                    // first tap on SearchView's input field doesn't pay
                    // the ~100-300ms cold start (loading IME, dictionary,
                    // key layout). Delayed 800ms so we don't fight the
                    // critical cold-start path (bookmark / cache hydrate
                    // / NSMetadataQuery) for main-thread time.
                    try? await Task.sleep(for: .milliseconds(800))
                    warmUpKeyboard()
                }
            // WebView warm-up is kicked off from the list views' `onAppear`
            // (see RecentNotesView / FoldersHomeView). That fires earlier in
            // cold-start than `WindowGroup.onAppear` and matches the moment
            // the user might be about to open a note.
        }
    }

    /// Pre-warm the iOS soft-keyboard subsystem.
    ///
    /// Why: the first `becomeFirstResponder` of a process triggers the
    /// keyboard system to load IME, dictionary, key layout, etc — a
    /// 100-300ms cost the user feels as "tap-then-wait" the first time
    /// they tap any text field. By doing the same dance on a hidden
    /// `UITextField` shortly after launch we move that cost off the
    /// user's interaction path.
    ///
    /// How: add a hidden field to the key window, become first responder,
    /// then resign on the next runloop tick (so the keyboard subsystem
    /// has a chance to actually initialise) and remove the field. The
    /// field is `isHidden = true` so there's no visual artefact.
    @MainActor
    private func warmUpKeyboard() {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
            let window = scene.windows.first(where: { $0.isKeyWindow })
                ?? scene.windows.first
        else { return }

        let field = UITextField(frame: .zero)
        field.isHidden = true
        window.addSubview(field)
        field.becomeFirstResponder()
        DispatchQueue.main.async {
            field.resignFirstResponder()
            field.removeFromSuperview()
        }
    }
}
