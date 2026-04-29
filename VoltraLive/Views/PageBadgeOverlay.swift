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
                Text(name)
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
    }
}

extension View {
    /// Shows a faint monospace page-name badge at bottom-leading. The
    /// `name` should be the Swift type name of the screen verbatim so the
    /// user can reference it back to the agent unambiguously.
    func pageBadge(_ name: String) -> some View {
        modifier(PageBadgeOverlay(name: name))
    }
}
