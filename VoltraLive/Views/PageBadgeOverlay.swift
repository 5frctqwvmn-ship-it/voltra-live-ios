// b66 V4.2: Page-name badge.
//
// User ask: "I want you to put on the bottom left of every page what you
// name that page on the app so that when I'm referring to it in my notes
// I can give you specific page directions and now I have to guess."
//
// Spec (locked via MC this session):
//   • Anchor: bottom-leading, above the home indicator.
//   • Text: Swift type name VERBATIM (e.g. "LiveCaptureViewV2"), monospaced.
//   • Visibility: ALWAYS visible in V4.2 TestFlight builds — not gated on
//     debug builds, not gated on a feature flag. The user explicitly asked
//     for the badge to be available on the test-flight build they hold in
//     their hand so they can give precise page-level directions back to the
//     agent. Once b66 ships and the user confirms the badge has served its
//     purpose, gate it behind a flag in a follow-up build.
//   • Color: faint mint — uses VoltraColor.textFaint (same dim cool-mint
//     used by other low-priority labels) so it does not compete with the
//     primary content. ~9 pt to stay below the visual noise floor.
//
// b70 V4.4 update (V4-D18):
//   • Render format is now "NN · ScreenName" where NN is the 2-digit
//     stable ID from `PageRegistry`. Unknown screens render as
//     "-- · ScreenName" (still useful, and the visible signal to add the
//     screen to PageRegistry).
//   • The modifier also mounts `.debugGridOverlay()`, so any screen that
//     page-badges automatically gets the debug grid (which is invisible
//     until the user taps the build badge to flip the mode).
//
// b72 V4.5 update (V4-D22):
//   • `.debugGridOverlay()` is now the progressive-density spreadsheet
//     grid (5 states) instead of the b70 9-anchor markers. Mount order
//     is unchanged: the grid is the LAST modifier in the chain so it
//     renders ABOVE this page-badge layer in z-order. Margin labels
//     therefore remain legible over the badge text.
//   • No layout change here. Screens that opt into the State 4 region
//     overlay use the new `.debugRegion("name")` modifier (declared in
//     `DebugGridOverlay.swift`); those calls go on the screen body, not
//     on this page badge.
//
// Usage:
//   SomeView()
//       .pageBadge("SomeView")
//
// The screen-name parameter is a String (not derived from #file or
// #function) so screens that wrap content in a NavigationStack or other
// container can still report the *user-visible* type name rather than
// some inner builder helper.

import SwiftUI

private struct PageBadgeOverlay: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                Text("\(PageRegistry.id(for: name)) · \(name)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(VoltraColor.textFaint)
                    .padding(.leading, 12)
                    // Sit just above the home indicator. SafeArea bottom
                    // already pushes us above the indicator on devices
                    // with one; the +4 is a small visual buffer.
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            // b70 / V4-D18: every page-badged screen also participates in
            // the debug-grid overlay. Renders nothing when
            // `debugGridMode == .off` (the default), so this is a no-op
            // on shipped builds until the user cycles the mode via the
            // build-badge tap.
            .debugGridOverlay()
    }
}

extension View {
    /// Shows a faint monospace page-name badge at bottom-leading. The
    /// `name` should be the Swift type name of the screen verbatim so the
    /// user can reference it back to the agent unambiguously.
    ///
    /// b70: render format is `"NN \u00B7 ScreenName"` where `NN` comes
    /// from `PageRegistry`. Also mounts the debug-grid overlay (off by
    /// default).
    func pageBadge(_ name: String) -> some View {
        modifier(PageBadgeOverlay(name: name))
    }
}
