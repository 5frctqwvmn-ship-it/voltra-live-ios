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
//
// b72 V4.5 update (V4-D22):
//   • The tap now cycles `DebugGridDensity` (off → base → half → quarter
//     → max → off) instead of the legacy four-state anchor overlay. Same
//     AppStorage key (`"debugGridMode"`) so a user with a persisted
//     legacy value (e.g. "corners") gracefully migrates to `.base` on
//     next tap via `DebugGridDensity.from(_:)`.
//   • The legacy `DebugGridMode` enum is kept in `DebugGridOverlay.swift`
//     behind a `// SUPERSEDED` marker for rollback — restoring the old
//     behavior is a one-line change here (cycle `DebugGridMode.next()`
//     instead of `DebugGridDensity.next()`).

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

    /// b72 / V4-D22: persisted grid density. Tapping the chip cycles this
    /// through the five `DebugGridDensity` cases. AppStorage key kept as
    /// `"debugGridMode"` for migration continuity from the legacy
    /// b70 / V4-D18 four-state enum (see `DebugGridDensity.from(_:)`).
    @AppStorage("debugGridMode") private var modeRaw: String = DebugGridDensity.off.rawValue

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
            // B74-F11: triple-tap unlocks the SessionRecorder dot.
            // Declared BEFORE the single-tap so SwiftUI's tap-count
            // disambiguation prefers it. A lone single tap still cycles
            // the grid (with a ~250 ms delay introduced by the
            // disambiguation window). Persisted in UserDefaults so the
            // unlock survives app launches.
            .onTapGesture(count: 3) {
                UserDefaults.standard.set(true, forKey: "VOLTRARecorderUnlocked")
            }
            .onTapGesture {
                let current = DebugGridDensity.from(modeRaw)
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
