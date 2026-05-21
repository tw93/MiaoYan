import Foundation

/// Semantic names for the magic delays scattered across `DispatchQueue.main.asyncAfter`.
///
/// **This does not eliminate time-coupling**, it just gives the existing
/// delays consistent labels so a future refactor can grep for one offender at
/// a time. Where possible, prefer event-based readiness (e.g. the
/// `MPreviewView.postReadyCallbacks` pattern) over any of these constants.
///
/// Ranges are picked from the existing call sites. If you find yourself
/// reaching for a value not represented here, that is usually a sign that the
/// site has a real readiness signal you should be subscribing to instead.
enum UIDelay {

    /// 0.1s. Standard "let the current run loop finish" pause. Used after
    /// triggering a view layout, popover frame change, or visibility toggle
    /// so that the next read of the resulting geometry sees the new value.
    static let short: TimeInterval = 0.1

    /// 0.3s. Standard "let the user perceive the previous step" pause. Used
    /// between two user-visible transitions to avoid stacking animations.
    static let medium: TimeInterval = 0.3

    /// 1.0s. "Long-running operation is probably done" pause. Used for one
    /// shot fade-out / cleanup steps; avoid in interactive paths.
    static let long: TimeInterval = 1.0
}
