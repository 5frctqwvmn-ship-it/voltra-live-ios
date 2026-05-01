// DebugGridOverlay.swift
// b72 V4.5 / V4-D22 — progressive-density spreadsheet-style debug grid.
// Replaces the b70 V4-D18 9-anchor marker overlay (C-TL / M-T / F-CTR / …)
// because anchor markers are not precise enough for design feedback.
//
// User ask (verbatim, captured in docs/handoff/B72_DEBUG_GRID_PROMPT.md):
//   "Give me a real spreadsheet-style graph-paper grid with column letters
//    and row numbers, and make the existing tap toggle progressively
//    increase density over 4 levels."
//
// 5-state cycle (advance via the build-badge tap, same surface as before):
//   0 .off      — no overlay rendered (default; shipped state).
//   1 .base     — 32pt graph-paper grid; column letters A,B,C,…,Z,AA,AB,…
//                 across the top margin strip; row numbers 1,2,3,… down the
//                 leading margin strip. Gridlines ~30 % opacity, labels ~75 %.
//   2 .half     — adds gridlines halfway between each base line, both axes.
//                 Half-step labels (A.5, 10.5, …) sit interior on the margin
//                 strips at reduced weight; base labels stay at full weight.
//   3 .quarter  — adds gridlines at every quarter step (.25, .75) on top of
//                 .half. Quarter labels are MARGIN-ONLY (top + leading
//                 strips); the screen body stays clean. Decision logged in
//                 V4-D22 ADR.
//   4 .max      — everything in .quarter PLUS a region-outline layer.
//                 Translucent rectangles with their Swift identifier name
//                 are drawn around major UI sections of the current screen.
//                 The page being inspected publishes its regions via the
//                 `.debugRegions(...)` modifier (preference key, declarative).
//                 Screens that do not opt in render the grid only at .max
//                 with no regions (graceful degradation).
//
// Style spec (per b72 prompt):
//   • 32pt base grid spacing (locked here as `Self.baseSpacing`).
//   • Gridlines: Canvas (single draw call). Base 0.6pt @30 %, half 0.4pt
//     @20 %, quarter 0.3pt @14 %.
//   • Labels: Text overlay layer at 8pt monospaced; mint
//     (VoltraColor.textFaint @ 0.85 base / 0.55 half / 0.45 quarter).
//   • Margin strips: 14pt top + 14pt leading. Sit on top of the safe-area
//     inset so labels do NOT slide under the iOS status bar / home
//     indicator on devices that have them.
//   • Region outlines (.max only): VoltraColor.accent stroked at 1pt with
//     0.40 opacity. Region label centered top-leading inside the region,
//     8pt monospaced.
//   • `.allowsHitTesting(false)` on every layer — overlay never blocks
//     touches. PageBadgeOverlay mounts this AFTER its own bottom-leading
//     badge, so the grid renders ABOVE the page badge and the build badge
//     in z-order.
//
// Persistence
//   AppStorage("debugGridMode") — re-used so a user who tapped through the
//   legacy overlay does not lose their setting. `DebugGridDensity.from(_:)`
//   migrates legacy raw values: "off" → .off, anything else → .base. The
//   user discovers the new behavior on next tap.
//
// Performance
//   Canvas draws all gridlines as straight Path strokes — no per-line view.
//   Label count caps at ~12 cols × ~26 rows (390×844) base, ×4 at quarter
//   density when margin-only labels are confined to the strips. No frame
//   drops observed in the simulator on iPhone 15.
//
// Sacred-files: untouched. No protocol/BLE files modified.

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
/// overlay. The screen calls `.debugRegion("name") { ... }` or attaches a
/// `.debugRegionAnchor("name")` to a child view; this module collects the
/// anchors via a preference key and renders rectangles when the density is
/// `.max`.
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

// MARK: - Modifier

private struct DebugGridOverlayModifier: ViewModifier {

    @AppStorage("debugGridMode") private var modeRaw: String =
        DebugGridDensity.off.rawValue

    private var density: DebugGridDensity {
        DebugGridDensity.from(modeRaw)
    }

    func body(content: Content) -> some View {
        content
            // Capture region anchors published by descendants. Reading
            // them here (above the overlay layer) means the grid layer
            // can resolve them via GeometryProxy.
            .overlayPreferenceValue(DebugRegionsPreferenceKey.self) { regions in
                if density != .off {
                    GeometryReader { proxy in
                        DebugGridCanvas(
                            density: density,
                            regions: regions,
                            proxy: proxy
                        )
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Canvas renderer

private struct DebugGridCanvas: View {

    let density: DebugGridDensity
    let regions: [DebugRegion]
    let proxy: GeometryProxy

    /// 32pt base spacing. Locked per V4-D22 — produces ~12 cols × ~26 rows
    /// on a 390×844 device, which is the recommended balance between
    /// graph-paper feel and label legibility at quarter-step density.
    private static let baseSpacing: CGFloat = 32

    /// Width of the leading row-number strip and height of the top
    /// column-letter strip, in points. Sized to clear iOS status-bar
    /// glyphs and home-indicator while keeping labels tight to the edge.
    private static let marginStrip: CGFloat = 14

    var body: some View {
        let safe = proxy.safeAreaInsets
        let w = proxy.size.width
        let h = proxy.size.height

        // The grid uses the FULL host frame so users can point at literal
        // screen edges. Margin strips, however, sit inside the safe area
        // so column letters don't disappear under the status bar and row
        // numbers don't sit under the home indicator.
        let stripTop = safe.top + 0   // labels start AT safe-area top
        let stripLeading = safe.leading + 0

        ZStack(alignment: .topLeading) {
            // 1) Gridlines — single Canvas draw call.
            Canvas { ctx, size in
                drawGridlines(ctx: &ctx, size: size)
            }
            .frame(width: w, height: h)

            // 2) Column letters across top margin strip.
            columnLabels(width: w, stripTop: stripTop)

            // 3) Row numbers down leading margin strip.
            rowLabels(height: h, stripLeading: stripLeading)

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
                skipMultiplesOf: 2  // skip the half-step lines
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
                skipMultiplesOf: 2  // skip the base lines
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

    /// Strokes vertical and horizontal gridlines at `spacing` intervals,
    /// optionally skipping every Nth line so finer-grain passes don't
    /// re-draw lines from a coarser pass.
    private func stroke(
        ctx: inout GraphicsContext,
        size: CGSize,
        spacing: CGFloat,
        lineWidth: CGFloat,
        color: Color,
        skipMultiplesOf: Int
    ) {
        var path = Path()
        // Vertical gridlines.
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
        // Horizontal gridlines.
        i = 0
        var y: CGFloat = 0
        while y <= size.height {
            if skipMultiplesOf == 0 || i % skipMultiplesOf != 0 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            i += 1
            y += spacing
        }
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // MARK: column letters (top margin)

    @ViewBuilder
    private func columnLabels(width: CGFloat, stripTop: CGFloat) -> some View {
        // Base columns: A, B, C, ... (32pt steps).
        // Half columns: A.5, B.5, ... (16pt offset, only at .half+).
        // Quarter columns: A.25, A.75, ... (8pt offset, MARGIN-ONLY at .quarter+).
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
            // Quarter — even more reduced; margin-only (which here means
            // we already ARE in the top margin strip, so all column
            // labels are margin labels). At quarter density we only show
            // .25 and .75; .5 is already drawn by the half pass.
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

    // MARK: row numbers (leading margin)

    @ViewBuilder
    private func rowLabels(height: CGFloat, stripLeading: CGFloat) -> some View {
        let drawHalf = (density == .half || density == .quarter || density == .max)
        let drawQuarter = (density == .quarter || density == .max)
        let count = Int(ceil(height / Self.baseSpacing)) + 1

        ZStack(alignment: .topLeading) {
            // Base — full weight. Row numbering starts at 1.
            ForEach(0..<count, id: \.self) { i in
                let y = CGFloat(i) * Self.baseSpacing
                Text("\(i + 1)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VoltraColor.textFaint.opacity(0.85))
                    .position(x: stripLeading + 8, y: y + 6)
            }
            if drawHalf {
                ForEach(0..<count, id: \.self) { i in
                    let y = CGFloat(i) * Self.baseSpacing + Self.baseSpacing / 2
                    Text("\(i + 1).5")
                        .font(.system(size: 7, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.55))
                        .position(x: stripLeading + 8, y: y)
                }
            }
            if drawQuarter {
                ForEach(0..<count, id: \.self) { i in
                    let y25 = CGFloat(i) * Self.baseSpacing + Self.baseSpacing * 0.25
                    let y75 = CGFloat(i) * Self.baseSpacing + Self.baseSpacing * 0.75
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
    func debugGridOverlay() -> some View {
        modifier(DebugGridOverlayModifier())
    }
}

// MARK: - SUPERSEDED — legacy 9-anchor overlay (b70 V4-D18)
//
// The original four-state anchor overlay (off/corners/midlines/full) lived
// here through b71. It was replaced in b72 by the progressive-density grid
// above. The legacy enum and helper are retained — but unmounted — so a
// rollback is a one-line change in `BuildBadgeOverlay.swift`'s tap handler
// (cycle the legacy enum instead) plus restoring the modifier body.
//
// Per AGENTS.md "Surface assumptions" + the b72 prompt's "Do not remove the
// existing overlay before the new one renders correctly" rule, we leave
// these symbols compiling but unreferenced. Delete after one clean ship of
// the new overlay (target: post-b73 if no rollback fires).

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
