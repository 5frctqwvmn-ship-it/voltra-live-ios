// DebugGridOverlay.swift
// b70 V4.4 / V4-D18 — four-state debug grid overlay that lets the user
// reference precise positions on any screen when giving feedback.
//
// User ask (continuation of the b66/b70 debug-surface work): "Give me a
// grid I can flip on so I can say 'between M-T and M-R, closer to C-TR'
// instead of 'between the third tile and the fourth tile near the bottom.'"
//
// Modes
// -----
//   .off      — invisible. Nothing rendered. Default; shipped state.
//   .corners  — four C-prefixed labels at the corners:
//                 C-TL  (top-leading)
//                 C-TR  (top-trailing)
//                 C-BL  (bottom-leading)
//                 C-BR  (bottom-trailing)
//   .midlines — four M-prefixed labels at edge midpoints:
//                 M-T   (top, horizontal center)
//                 M-R   (trailing, vertical center)
//                 M-B   (bottom, horizontal center)
//                 M-L   (leading, vertical center)
//   .full     — corners + midlines + a single F-CTR center label.
//
// Visual style
// ------------
// 9pt monospaced text, mint tint (`VoltraColor.textFaint`), opacity 0.85.
// Matches the existing page-badge typography so the overlay feels like
// part of the same chrome layer rather than a competing surface.
//
// Persistence
// -----------
// State lives in `@AppStorage("debugGridMode")` so it survives launches and
// is shared across every screen that mounts the overlay. The toggle
// gesture is on the build badge (`BuildBadgeOverlay.swift`) — tap cycles
// `.off → .corners → .midlines → .full → .off`. No other UI surface
// exposes the toggle (intentional — this is a debug affordance, not a
// product feature).
//
// Mounting
// --------
// `PageBadgeOverlay` mounts `.debugGridOverlay()` automatically, so any
// screen that calls `.pageBadge("...")` participates. Screens that don't
// page-badge (none today, but possible in future) can opt in directly
// with `.debugGridOverlay()`.

import SwiftUI

/// Persisted mode for the debug grid overlay. Codes as a String for
/// `@AppStorage`-friendly storage; the persisted key is `"debugGridMode"`.
enum DebugGridMode: String, CaseIterable {
    case off
    case corners
    case midlines
    case full

    /// Returns the next mode in the cycle. Used by the build-badge tap
    /// handler to advance through states.
    func next() -> DebugGridMode {
        switch self {
        case .off:      return .corners
        case .corners:  return .midlines
        case .midlines: return .full
        case .full:     return .off
        }
    }
}

private struct DebugGridOverlayModifier: ViewModifier {

    @AppStorage("debugGridMode") private var modeRaw: String = DebugGridMode.off.rawValue

    private var mode: DebugGridMode {
        DebugGridMode(rawValue: modeRaw) ?? .off
    }

    func body(content: Content) -> some View {
        content.overlay {
            // Off: render nothing. Avoids the GeometryReader allocation
            // and the per-frame layout pass for the common case.
            if mode != .off {
                gridOverlay
                    .opacity(0.85)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var gridOverlay: some View {
        // GeometryReader gives us the host's actual frame so the labels
        // hit real corners / midpoints rather than the safe-area inset.
        // The page-badge anchor uses the safe area; debug-grid labels
        // intentionally use the *full* host frame so they include the
        // top status-bar region and the home-indicator region — the user
        // wants to be able to point at literal screen edges.
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack(alignment: .topLeading) {
                if mode == .corners || mode == .full {
                    label("C-TL").position(x: anchor, y: anchor)
                    label("C-TR").position(x: w - anchor, y: anchor)
                    label("C-BL").position(x: anchor, y: h - anchor)
                    label("C-BR").position(x: w - anchor, y: h - anchor)
                }
                if mode == .midlines || mode == .full {
                    label("M-T").position(x: w / 2, y: anchor)
                    label("M-R").position(x: w - anchor, y: h / 2)
                    label("M-B").position(x: w / 2, y: h - anchor)
                    label("M-L").position(x: anchor, y: h / 2)
                }
                if mode == .full {
                    label("F-CTR").position(x: w / 2, y: h / 2)
                }
            }
            .frame(width: w, height: h)
        }
    }

    /// Inset from each edge in points. Big enough to clear the home
    /// indicator / status bar in normal portrait, small enough that
    /// the labels still feel "at the edge."
    private let anchor: CGFloat = 14

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(VoltraColor.textFaint)
    }
}

extension View {
    /// Applies the persisted debug-grid overlay. Reads
    /// `@AppStorage("debugGridMode")`; renders nothing when `.off`.
    /// Mounted automatically by `pageBadge(_:)` so most screens get it
    /// without an explicit call.
    func debugGridOverlay() -> some View {
        modifier(DebugGridOverlayModifier())
    }
}
