// DebugGridOverlay.swift
// b73 V4.5 / V4-D23 — scroll-anchored progressive-density debug grid.
//
// This file is the b73 evolution of the b72 grid (V4-D22). The visual
// language is identical (5-state cycle, 32 pt base, mint margin labels,
// region overlay at .max). The change in b73 is the COORDINATE SYSTEM:
//
//   • Vertical gridlines + column letters (A, B, C…) stay pinned to the
//     viewport horizontally — there is no horizontal scroll, so column
//     coordinates are stable in screen space.
//
//   • Horizontal gridlines + row numbers (1, 2, 3…) anchor to the
//     SCROLLVIEW CONTENT'S coordinate space, not the viewport. Row 1
//     means "the top of the content," not "the top of the screen." On
//     scroll, row labels travel with the content; "C10" means the same
//     UI element regardless of scroll offset.
//
// The bug in b72: the overlay was attached at the screen-body level
// (above any ScrollView), so a coordinate like "C10" pointed at a
// physical screen pixel — which mapped to a *different UI element* once
// the user scrolled. Two screenshots of LoggingHomeView (top vs
// scrolled) showed LEG DAY at row 5 in one and row 11 in the other.
// That breaks the whole point of having a coordinate system.
//
// V4-D23 ADR captures the fix: column letters are viewport-pinned, row
// numbers are content-pinned. Implementation uses a PreferenceKey piped
// from a `.debugGridContent()` modifier on the ScrollView's content
// container (typically the inner VStack). The preference reports two
// numbers per screen: the content's minY in the viewport coordinate
// space (negative as the user scrolls down) and the content's height.
// The overlay reads those, draws horizontal lines / row labels offset
// by `contentMinY`, and extends the row range to cover the full
// content height.
//
// Backward compatibility: screens that DON'T mount `.debugGridContent()`
// still work — the preference defaults to `(minY: 0, height: 0)` which
// means "I'm not scrollable; treat row 1 as viewport-top." This matches
// the b72 behavior for non-scrolling screens like ConnectView.
//
// User ask (b72 verbatim, captured in docs/handoff/B72_DEBUG_GRID_PROMPT.md):
//   "Give me a real spreadsheet-style graph-paper grid with column letters
//    and row numbers, and make the existing tap toggle progressively
//    increase density over 4 levels."
//
// b73 user follow-up (verbatim):
//   "The current DebugGridOverlay is mounted at the window/viewport
//    level, so gridline row numbers stay pinned to the physical screen
//    while the UI content scrolls independently. Make the grid travel
//    with the scrollable content."
//
// 5-state cycle (advance via the build-badge tap, same surface as before):
//   0 .off      — no overlay rendered (default; shipped state).
//   1 .base     — 32pt graph-paper grid; column letters A,B,C,…,Z,AA,…
//                 across the top margin strip; row numbers 1,2,3,… down
//                 the leading margin strip starting at content-top.
//   2 .half     — adds gridlines halfway between each base line.
//   3 .quarter  — adds gridlines at every quarter step. Quarter labels
//                 are MARGIN-ONLY.
//   4 .max      — everything in .quarter PLUS region outlines.
//
// Sacred files: untouched. No protocol/BLE files modified.

import SwiftUI

// MARK: - Density enum (canonical b72 source of truth)

/// 5-state density cycle for the debug grid overlay. AppStorage key:
/// `"debugGridMode"` (re-used from legacy overlay so persisted user
/// preference survives the upgrade).
enum DebugGridDensity: String, CaseIterable {
    case off
    case base
    case half
    case quarter
    case max

    /// Cycle forward. Used by the build-badge tap handler.
    func next() -> DebugGridDensity {
        switch self {
        case .off:     return .base
        case .base:    return .half
        case .half:    return .quarter
        case .quarter: return .max
        case .max:     return .off
        }
    }

    /// Read from the persisted AppStorage raw value, gracefully migrating
    /// legacy `DebugGridMode` values.
    static func from(_ raw: String) -> DebugGridDensity {
        if let v = DebugGridDensity(rawValue: raw) { return v }
        // Legacy migration: "off" stays off; anything else (corners,
        // midlines, full) maps to .base so the user gets the new grid
        // immediately and discovers the additional states by tapping.
        if raw == "off" { return .off }
        if raw.isEmpty { return .off }
        return .base
    }
}

// MARK: - Region preference (State 4)

/// A named UI region published by a screen for the State 4 region-outline
/// overlay. The screen calls `.debugRegion("name")` on a child view; this
/// module collects the anchors via a preference key and renders rectangles
/// when the density is `.max`.
struct DebugRegion: Equatable {
    let name: String
    let anchor: Anchor<CGRect>
}

private struct DebugRegionsPreferenceKey: PreferenceKey {
    static var defaultValue: [DebugRegion] = []
    static func reduce(value: inout [DebugRegion], nextValue: () -> [DebugRegion]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Publishes the receiver's bounding rect as a named region for the
    /// State 4 debug-grid overlay. No-op when the overlay is off or below
    /// `.max` density. Intended to be attached to view-builder bodies that
    /// already exist in the screen — does not change layout, does not
    /// intercept hits.
    ///
    /// Usage:
    /// ```swift
    /// HeaderPillRow().debugRegion("headerPillRow")
    /// ```
    func debugRegion(_ name: String) -> some View {
        anchorPreference(
            key: DebugRegionsPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [DebugRegion(name: name, anchor: anchor)]
        }
    }
}

// MARK: - Content metrics preference (b73 V4-D23)

/// Metrics piped up from a `.debugGridContent()` modifier so the
/// overlay can render row numbers in the content's coordinate space
/// instead of the viewport's.
///
/// `minY` is the y-offset of the content's top edge measured in the
/// `debugGridViewport` named coordinate space, which is established by
/// the overlay modifier itself. At rest it equals the content's top
/// padding (often 0); when the user scrolls down, it becomes negative.
///
/// `height` is the full intrinsic content height (which may exceed the
/// viewport height — that's the entire point: row labels need to cover
/// the full content extent).
struct DebugGridContentMetrics: Equatable {
    var minY: CGFloat
    var height: CGFloat

    /// Default for screens that do NOT call `.debugGridContent()` —
    /// matches the b72 behavior (rows pinned to viewport top, height
    /// driven by the overlay's GeometryProxy).
    static let zero = DebugGridContentMetrics(minY: 0, height: 0)
}

private struct DebugGridContentMetricsKey: PreferenceKey {
    static var defaultValue: DebugGridContentMetrics = .zero
    /// Last-writer-wins. There should be exactly one `.debugGridContent()`
    /// per screen; if a developer accidentally attaches two we take the
    /// inner one. (No defensive sum/max — a duplicate is a misuse.)
    static func reduce(value: inout DebugGridContentMetrics,
                       nextValue: () -> DebugGridContentMetrics) {
        value = nextValue()
    }
}

extension View {
    /// Marks the receiver as the SCROLLABLE CONTENT CONTAINER for the
    /// debug grid overlay. Attach to the inner VStack/LazyVStack that
    /// lives inside a ScrollView so its rows track scroll position.
    ///
    /// Mechanic: a transparent GeometryReader background measures the
    /// receiver's frame in the `"debugGridViewport"` named coordinate
    /// space (which the overlay establishes on the same screen). The
    /// resulting `(minY, height)` is published via the
    /// `DebugGridContentMetricsKey` preference; the overlay reads it and
    /// translates horizontal gridlines + row labels by `minY` so they
    /// travel with the content as the user scrolls.
    ///
    /// A no-op (cosmetically and behaviorally) when the overlay is off.
    /// Hit testing: the GeometryReader is a `.background` only — does
    /// not affect layout or block touches.
    ///
    /// Usage:
    /// ```swift
    /// ScrollView {
    ///     VStack {
    ///         …
    ///     }
    ///     .debugGridContent()  // ← here, on the inner stack
    /// }
    /// ```
    func debugGridContent() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: DebugGridContentMetricsKey.self,
                        value: DebugGridContentMetrics(
                            minY: proxy.frame(in: .named("debugGridViewport")).minY,
                            height: proxy.size.height
                        )
                    )
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        )
    }
}

// MARK: - Modifier

private struct DebugGridOverlayModifier: ViewModifier {

    @AppStorage("debugGridMode") private var modeRaw: String =
        DebugGridDensity.off.rawValue

    /// Most recent metrics piped up from a `.debugGridContent()`
    /// descendant. Defaults to `.zero` for screens that don't have a
    /// scroll container (ConnectView etc.) — in that case the row
    /// numbers stay pinned to the viewport, matching b72 behavior.
    @State private var contentMetrics: DebugGridContentMetrics = .zero

    private var density: DebugGridDensity {
        DebugGridDensity.from(modeRaw)
    }

    func body(content: Content) -> some View {
        content
            // Establish the named coordinate space the
            // `.debugGridContent()` modifier measures itself against.
            // Putting it here means EVERY descendant — including the
            // ScrollView's content — resolves `minY` consistently.
            .coordinateSpace(name: "debugGridViewport")
            // Capture region anchors published by descendants so we can
            // resolve them via the GeometryProxy in the overlay layer
            // (State 4).
            .overlayPreferenceValue(DebugRegionsPreferenceKey.self) { regions in
                if density != .off {
                    GeometryReader { proxy in
                        DebugGridCanvas(
                            density: density,
                            regions: regions,
                            proxy: proxy,
                            contentMetrics: contentMetrics
                        )
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
            // Subscribe to content-metrics updates from descendants
            // marked with `.debugGridContent()`. Updates flow up
            // every layout pass while scrolling, so row labels follow
            // the scroll smoothly.
            .onPreferenceChange(DebugGridContentMetricsKey.self) { metrics in
                contentMetrics = metrics
            }
    }
}

// MARK: - Canvas renderer

private struct DebugGridCanvas: View {

    let density: DebugGridDensity
    let regions: [DebugRegion]
    let proxy: GeometryProxy
    let contentMetrics: DebugGridContentMetrics

    /// 32pt base spacing. Locked per V4-D22 — produces ~12 cols × ~26 rows
    /// on a 390×844 device, which is the recommended balance between
    /// graph-paper feel and label legibility at quarter-step density.
    private static let baseSpacing: CGFloat = 32

    /// Width of the leading row-number strip and height of the top
    /// column-letter strip, in points. Sized to clear iOS status-bar
    /// glyphs and home-indicator while keeping labels tight to the edge.
    private static let marginStrip: CGFloat = 14

    /// Where row 1 sits, in viewport coordinates. Equals the content's
    /// minY in the viewport coordinate space — at rest 0 or a small
    /// positive top inset, scrolling down it becomes negative so row 1
    /// scrolls off-screen and the user sees rows 2, 3, 4… in the
    /// margin strip. Falls back to 0 (viewport-top) for non-scrolling
    /// screens that don't call `.debugGridContent()`.
    private var contentOriginY: CGFloat { contentMetrics.minY }

    /// Total vertical extent the row labels need to cover. For a
    /// scrollable screen this is the full content height; for a
    /// non-scrollable screen it falls back to the viewport height (so
    /// rows still cover the visible area).
    private var rowExtent: CGFloat {
        contentMetrics.height > 0 ? contentMetrics.height : proxy.size.height
    }

    var body: some View {
        let safe = proxy.safeAreaInsets
        let w = proxy.size.width
        let h = proxy.size.height

        // The grid uses the FULL host frame so users can point at literal
        // screen edges. Margin strips, however, sit inside the safe area
        // so column letters don't disappear under the status bar.
        let stripTop = safe.top + 0
        let stripLeading = safe.leading + 0

        ZStack(alignment: .topLeading) {
            // 1) Gridlines — single Canvas draw call.
            Canvas { ctx, size in
                drawGridlines(ctx: &ctx, size: size)
            }
            .frame(width: w, height: h)
            // Clip horizontally to the viewport. The Canvas itself
            // honors `contentOriginY` for the horizontal-line pass
            // (see `drawGridlines`).

            // 2) Column letters across top margin strip — VIEWPORT pinned.
            columnLabels(width: w, stripTop: stripTop)

            // 3) Row numbers down leading margin strip — CONTENT pinned.
            //    Translated by `contentOriginY` so they scroll with the
            //    content. Clipped to the viewport so the strip doesn't
            //    bleed labels off-screen.
            rowLabels(stripLeading: stripLeading)
                .frame(width: w, height: h, alignment: .topLeading)
                .clipped()

            // 4) Region overlay (State 4 only).
            if density == .max {
                regionOverlay(proxy: proxy)
            }
        }
        .frame(width: w, height: h)
    }

    // MARK: gridline drawing

    private func drawGridlines(ctx: inout GraphicsContext, size: CGSize) {
        // Quarter step = 8pt, half = 16pt, base = 32pt. We draw whichever
        // levels are active for the current density.
        let drawQuarter = (density == .quarter || density == .max)
        let drawHalf = (density == .half || drawQuarter)

        // QUARTER first (most subordinate, drawn underneath others).
        if drawQuarter {
            stroke(
                ctx: &ctx,
                size: size,
                spacing: Self.baseSpacing / 4,
                lineWidth: 0.3,
                color: VoltraColor.textFaint.opacity(0.14),
                skipMultiplesOf: 2
            )
        }
        // HALF.
        if drawHalf {
            stroke(
                ctx: &ctx,
                size: size,
                spacing: Self.baseSpacing / 2,
                lineWidth: 0.4,
                color: VoltraColor.textFaint.opacity(0.20),
                skipMultiplesOf: 2
            )
        }
        // BASE — always drawn (any density >= .base).
        stroke(
            ctx: &ctx,
            size: size,
            spacing: Self.baseSpacing,
            lineWidth: 0.6,
            color: VoltraColor.textFaint.opacity(0.30),
            skipMultiplesOf: 0
        )
    }

    /// Strokes vertical gridlines (viewport-anchored, full height) and
    /// horizontal gridlines (content-anchored: shifted by
    /// `contentOriginY` and extended over the full content height,
    /// then clipped to the viewport).
    private func stroke(
        ctx: inout GraphicsContext,
        size: CGSize,
        spacing: CGFloat,
        lineWidth: CGFloat,
        color: Color,
        skipMultiplesOf: Int
    ) {
        var path = Path()

        // Vertical gridlines — VIEWPORT space, full height.
        var i = 0
        var x: CGFloat = 0
        while x <= size.width {
            if skipMultiplesOf == 0 || i % skipMultiplesOf != 0 {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            i += 1
            x += spacing
        }

        // Horizontal gridlines — CONTENT space.
        // Row 0 sits at y = contentOriginY in viewport coords. The
        // content extends from contentOriginY to (contentOriginY +
        // rowExtent). Draw lines across that range, then visually clip
        // to the viewport (Canvas clips to its own frame automatically,
        // so lines outside [0, size.height] simply don't render).
        let originY = contentOriginY
        let extent = rowExtent
        i = 0
        var y: CGFloat = 0
        // Continue until we've covered the full content extent. This
        // matters at higher densities where the user scrolls deep into
        // a long page — without this, the grid would visibly stop at
        // the viewport floor and the user couldn't reference row N
        // when N is off-screen-bottom.
        while y <= extent {
            if skipMultiplesOf == 0 || i % skipMultiplesOf != 0 {
                let yViewport = originY + y
                // Only emit if the line is inside (or near) the
                // viewport — small optimization, not a correctness
                // requirement (Canvas would clip anyway).
                if yViewport >= -spacing && yViewport <= size.height + spacing {
                    path.move(to: CGPoint(x: 0, y: yViewport))
                    path.addLine(to: CGPoint(x: size.width, y: yViewport))
                }
            }
            i += 1
            y += spacing
        }
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // MARK: column letters (top margin) — VIEWPORT pinned

    @ViewBuilder
    private func columnLabels(width: CGFloat, stripTop: CGFloat) -> some View {
        let drawHalf = (density == .half || density == .quarter || density == .max)
        let drawQuarter = (density == .quarter || density == .max)

        ZStack(alignment: .topLeading) {
            // Base — full weight.
            ForEach(baseColumnIndices(width: width), id: \.self) { i in
                let x = CGFloat(i) * Self.baseSpacing
                Text(columnLetters(for: i))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VoltraColor.textFaint.opacity(0.85))
                    .position(x: x + 6, y: stripTop + 7)
            }
            // Half — reduced weight.
            if drawHalf {
                ForEach(baseColumnIndices(width: width).dropLast(), id: \.self) { i in
                    let x = CGFloat(i) * Self.baseSpacing + Self.baseSpacing / 2
                    Text("\(columnLetters(for: i)).5")
                        .font(.system(size: 7, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.55))
                        .position(x: x, y: stripTop + 7)
                }
            }
            // Quarter — even more reduced; margin-only (.25 / .75).
            if drawQuarter {
                ForEach(baseColumnIndices(width: width).dropLast(), id: \.self) { i in
                    let xq25 = CGFloat(i) * Self.baseSpacing + Self.baseSpacing * 0.25
                    let xq75 = CGFloat(i) * Self.baseSpacing + Self.baseSpacing * 0.75
                    Text("\(columnLetters(for: i)).25")
                        .font(.system(size: 6, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.45))
                        .position(x: xq25, y: stripTop + 7)
                    Text("\(columnLetters(for: i)).75")
                        .font(.system(size: 6, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.45))
                        .position(x: xq75, y: stripTop + 7)
                }
            }
        }
    }

    private func baseColumnIndices(width: CGFloat) -> [Int] {
        let count = Int(ceil(width / Self.baseSpacing)) + 1
        return Array(0..<count)
    }

    /// 0 → "A", 1 → "B", …, 25 → "Z", 26 → "AA", 27 → "AB", …
    /// Spreadsheet-style column letters with wraparound.
    private func columnLetters(for index: Int) -> String {
        var n = index
        var s = ""
        repeat {
            s = String(UnicodeScalar(65 + (n % 26))!) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }

    // MARK: row numbers (leading margin) — CONTENT pinned (b73 V4-D23)

    @ViewBuilder
    private func rowLabels(stripLeading: CGFloat) -> some View {
        let drawHalf = (density == .half || density == .quarter || density == .max)
        let drawQuarter = (density == .quarter || density == .max)

        // Number of base rows over the full content extent. Adding +2
        // ensures the bottom edge gets a label even when content height
        // isn't an exact multiple of `baseSpacing`.
        let count = Int(ceil(rowExtent / Self.baseSpacing)) + 2
        let originY = contentOriginY

        ZStack(alignment: .topLeading) {
            // Base — full weight. Row 1 sits at content-top (originY).
            ForEach(0..<count, id: \.self) { i in
                let y = originY + CGFloat(i) * Self.baseSpacing
                Text("\(i + 1)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VoltraColor.textFaint.opacity(0.85))
                    .position(x: stripLeading + 8, y: y + 6)
            }
            if drawHalf {
                ForEach(0..<count, id: \.self) { i in
                    let y = originY + CGFloat(i) * Self.baseSpacing + Self.baseSpacing / 2
                    Text("\(i + 1).5")
                        .font(.system(size: 7, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.55))
                        .position(x: stripLeading + 8, y: y)
                }
            }
            if drawQuarter {
                ForEach(0..<count, id: \.self) { i in
                    let y25 = originY + CGFloat(i) * Self.baseSpacing + Self.baseSpacing * 0.25
                    let y75 = originY + CGFloat(i) * Self.baseSpacing + Self.baseSpacing * 0.75
                    Text("\(i + 1).25")
                        .font(.system(size: 6, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.45))
                        .position(x: stripLeading + 8, y: y25)
                    Text("\(i + 1).75")
                        .font(.system(size: 6, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.45))
                        .position(x: stripLeading + 8, y: y75)
                }
            }
        }
    }

    // MARK: region overlay (State 4)

    @ViewBuilder
    private func regionOverlay(proxy: GeometryProxy) -> some View {
        ForEach(regions, id: \.name) { region in
            let rect = proxy[region.anchor]
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(VoltraColor.accent.opacity(0.40), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                Text(region.name)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VoltraColor.accent.opacity(0.85))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        Color.black.opacity(0.55)
                            .cornerRadius(2)
                    )
                    .padding(.leading, 3)
                    .padding(.top, 3)
            }
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .offset(x: rect.minX, y: rect.minY)
        }
    }
}

// MARK: - Public modifier API

extension View {
    /// Mounts the progressive-density debug grid overlay. Reads
    /// `@AppStorage("debugGridMode")`; renders nothing when `.off`.
    /// Mounted automatically by `pageBadge(_:)` so most screens get it
    /// for free. Hit-testing disabled, so the overlay never blocks UI
    /// underneath.
    ///
    /// Pair with `.debugGridContent()` on the inner ScrollView content
    /// container to make row numbers travel with scroll (b73 / V4-D23).
    /// Screens without scroll content can omit it — row numbers
    /// gracefully fall back to viewport-pinned (matching b72 behavior).
    func debugGridOverlay() -> some View {
        modifier(DebugGridOverlayModifier())
    }
}

// MARK: - SUPERSEDED — legacy 9-anchor overlay (b70 V4-D18)
//
// The original four-state anchor overlay (off/corners/midlines/full)
// lived here through b71. It was replaced in b72 by the
// progressive-density grid above, then refined in b73 to be
// scroll-anchored. The legacy enum is retained — but unmounted — so a
// rollback is a one-line change in `BuildBadgeOverlay.swift`'s tap
// handler (cycle the legacy enum instead) plus restoring the modifier
// body.
//
// Per AGENTS.md "Surface assumptions" + the b72 prompt's "Do not remove
// the existing overlay before the new one renders correctly" rule, we
// leave these symbols compiling but unreferenced. Delete after one
// clean ship of the new overlay (target: post-b74 if no rollback fires).

/// SUPERSEDED in b72 / V4-D22. Retained for rollback. Do not reference.
enum DebugGridMode: String, CaseIterable {
    case off
    case corners
    case midlines
    case full

    func next() -> DebugGridMode {
        switch self {
        case .off:      return .corners
        case .corners:  return .midlines
        case .midlines: return .full
        case .full:     return .off
        }
    }
}
