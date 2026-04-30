// BuildBadgeOverlay.swift
// Global build-version chip rendered as an overlay so the version shows up
// on every screenshot the user sends me. Avoids "is this the new build or
// not?" debugging.
//
// Usage:
//     SomeView().buildBadgeOverlay()
//
// Applied at:
//   - ContentView (covers Connect, Home, all pushed nav destinations)
//   - any full-screen sheet that completely covers the root (ExportSheet,
//     SetLogView, DebugView, custom-day sheet)
//
// Layout is bottom-trailing in the safe area. Small monospace text on a
// faintly-tinted pill so it stays readable over both dark backgrounds and
// brighter content (alerts/sheets) without being visually loud.
//
// b70 V4.4 update (V4-D18):
//   • Tapping the chip now cycles `@AppStorage("debugGridMode")` through
//     the four `DebugGridMode` cases (off → corners → midlines → full →
//     off). The chip layout / colors / position are unchanged.
//   • The chip is the only UI surface that toggles the grid — keeps the
//     gesture in a place the user already looks for during chrome
//     inspection, no new affordances added.

import SwiftUI

struct BuildBadgeOverlay: ViewModifier {

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                BuildBadgeChip()
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                // b70 / V4-D18: chip is now tappable to cycle the debug
                // grid. `allowsHitTesting(false)` was previously global on
                // the chip; we drop it so the tap registers. The page
                // badge (sibling overlay at bottom-leading) keeps
                // `allowsHitTesting(false)` so it can never intercept.
            }
    }
}

private struct BuildBadgeChip: View {

    /// b70 / V4-D18: persisted grid mode. Tapping the chip cycles this
    /// through the four `DebugGridMode` cases.
    @AppStorage("debugGridMode") private var modeRaw: String = DebugGridMode.off.rawValue

    var body: some View {
        Text(versionString)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(VoltraColor.textDim.opacity(0.85))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                Capsule()
                    .stroke(VoltraColor.border.opacity(0.6), lineWidth: 0.5)
            )
            // Tap cycles the debug-grid mode. Contained inside the chip
            // so the rest of the screen retains its normal hit-testing.
            // contentShape ensures the entire capsule (including the
            // padding) is tappable, not just the rendered glyph rect.
            .contentShape(Capsule())
            .onTapGesture {
                let current = DebugGridMode(rawValue: modeRaw) ?? .off
                modeRaw = current.next().rawValue
            }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        // Build 31: optional per-build feature label so the user can tell
        // at a glance which single feature this build is testing. Set via
        // VOLTRAFeatureLabel in Info.plist (kept short to avoid wrapping).
        // Empty / missing = no label, behaves like prior builds.
        let feature = (info["VOLTRAFeatureLabel"] as? String) ?? ""
        if feature.isEmpty {
            return "v\(short) (\(build))"
        }
        return "v\(short) (\(build)) · \(feature)"
    }
}

extension View {
    /// Floats a small "v<short> (<build>)" chip over the bottom-trailing
    /// corner so the running build is visible in every screenshot.
    func buildBadgeOverlay() -> some View {
        modifier(BuildBadgeOverlay())
    }
}

#Preview {
    ZStack {
        VoltraColor.bg.ignoresSafeArea()
        Text("Sample screen content")
            .foregroundColor(VoltraColor.text)
    }
    .buildBadgeOverlay()
    .preferredColorScheme(.dark)
}
