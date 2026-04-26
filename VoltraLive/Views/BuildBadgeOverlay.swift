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

import SwiftUI

struct BuildBadgeOverlay: ViewModifier {

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                BuildBadgeChip()
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
    }
}

private struct BuildBadgeChip: View {
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
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (\(build))"
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
