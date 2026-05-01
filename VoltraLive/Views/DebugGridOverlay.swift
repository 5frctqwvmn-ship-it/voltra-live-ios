// DebugGridOverlay.swift
// b74 V4.6 / V4-D24 — content-space debug grid (true scroll-anchored).
//
// b74 RATIONALE (corrects b73 / V4-D23):
//
//   The b73 attempt used a PreferenceKey (`DebugGridContentMetricsKey`)
//   piped from `.debugGridContent()` to translate horizontal lines + row
//   labels by `contentMinY`. The grid still rendered in a viewport-level
//   overlay above the ScrollView. On real hardware the grid behaved as a
//   viewport overlay regardless of scroll — the translation pass either
//   never updated, never rendered, or rendered behind clipping. The shipped
//   build (b73 / v0.4.46) failed on device.
//
//   b74 abandons the PreferenceKey path entirely. Horizontal gridlines
//   and row labels physically live INSIDE the ScrollView's scrollable
//   content, attached to the inner content container via
//   `.background(DebugGridContentLayer())`. SwiftUI's background sizing
//   makes the layer's frame match its host's intrinsic frame — so the
//   grid covers the FULL content extent, scrolls with content for free,
//   and there is no preference-key plumbing or named-coordinate-space
//   translation involved. Row 1 sits at the top of content, row N is
//   meaningful at any scroll offset, and "C10" identifies the same UI
//   element regardless of where the user has scrolled.
//
//   Vertical gridlines and column letters remain VIEWPORT-pinned in the
//   screen-body overlay (where they belong — there is no horizontal
//   scroll, so column coordinates are stable in screen space). The
//   `.max` density region overlay also stays viewport-level via the
//   existing `anchorPreference` mechanism.
//
//   `.allowsHitTesting(false)` everywhere — the grid never blocks UI.
//
// V4-D22 density states preserved verbatim:
//   0 .off      — no overlay rendered.
//   1 .base     — 32pt graph-paper grid; column letters A,B,C,…; row
//                 numbers 1,2,3,… starting at the top of CONTENT.
//   2 .half     — adds gridlines halfway between each base line.
//   3 .quarter  — adds gridlines at every quarter step. Quarter labels
//                 are MARGIN-ONLY.
//   4 .max      — everything in .quarter PLUS region outlines.
//
// User ask (b74 verbatim):
//   "Remove the b73 PreferenceKey / contentMinY path entirely.
//    Implement a real DebugGridContentLayer attached via .background(...)
//    on each ScrollView content container. Horizontal gridlines and row
//    labels must physically live inside and scroll with content."
//
// Sacred files: untouched. No protocol/BLE/release/signing changes.

import SwiftUI

// MARK: - Density enum (canonical b72 source of truth — unchanged)

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

// MARK: - DebugGridContentLayer (b74 V4-D24)

/// The content-space half of the debug grid. Draws horizontal gridlines
/// + row labels SIZED TO ITS HOST'S INTRINSIC FRAME, so when attached
/// via `.background(...)` to a ScrollView's inner content container the
/// layer covers the full scrollable content — and scrolls with it for
/// free, because the layer is genuinely a sibling of that content.
///
/// No PreferenceKey, no named coordinate space, no translation pass. The
/// layer's frame IS the content's frame. SwiftUI handles the rest.
///
/// Reads `@AppStorage("debugGridMode")` directly so density updates
/// without a state hand-off from the parent overlay.
struct DebugGridContentLayer: View {

    @AppStorage("debugGridMode") private var modeRaw: String =
        DebugGridDensity.off.rawValue

    private var density: DebugGridDensity {
        DebugGridDensity.from(modeRaw)
    }

    /// 32pt base spacing — locked per V4-D22.
    private static let baseSpacing: CGFloat = 32

    /// Width of the leading row-number strip (matches the viewport
    /// overlay's strip so labels align visually).
    private static let marginStrip: CGFloat = 14

    var body: some View {
        // Skip rendering entirely when off — keeps the .background()
        // attachment a no-op on shipped builds.
        if density == .off {
            Color.clear
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    // Horizontal gridlines, sized to content height.
                    Canvas { ctx, size in
                        drawHorizontalLines(ctx: &ctx, size: size)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)

                    // Row labels — sit in the leading margin strip.
                    rowLabels(height: proxy.size.height)
                }
                .frame(width: proxy.size.width, height: proxy.size.height,
                       alignment: .topLeading)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    // MARK: horizontal gridlines

    private func drawHorizontalLines(ctx: inout GraphicsContext, size: CGSize) {
        let drawQuarter = (density == .quarter || density == .max)
        let drawHalf = (density == .half || drawQuarter)

        if drawQuarter {
            strokeHorizontals(
                ctx: &ctx,
                size: size,
                spacing: Self.baseSpacing / 4,
                lineWidth: 0.3,
                color: VoltraColor.textFaint.opacity(0.14),
                skipMultiplesOf: 2
            )
        }
        if drawHalf {
            strokeHorizontals(
                ctx: &ctx,
                size: size,
                spacing: Self.baseSpacing / 2,
                lineWidth: 0.4,
                color: VoltraColor.textFaint.opacity(0.20),
                skipMultiplesOf: 2
            )
        }
        // Base — always drawn.
        strokeHorizontals(
            ctx: &ctx,
            size: size,
            spacing: Self.baseSpacing,
            lineWidth: 0.6,
            color: VoltraColor.textFaint.opacity(0.30),
            skipMultiplesOf: 0
        )
    }

    private func strokeHorizontals(
        ctx: inout GraphicsContext,
        size: CGSize,
        spacing: CGFloat,
        lineWidth: CGFloat,
        color: Color,
        skipMultiplesOf: Int
    ) {
        var path = Path()
        var i = 0
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

    // MARK: row labels (content-space)

    @ViewBuilder
    private func rowLabels(height: CGFloat) -> some View {
        let drawHalf = (density == .half || density == .quarter || density == .max)
        let drawQuarter = (density == .quarter || density == .max)

        let count = Int(ceil(height / Self.baseSpacing)) + 2

        ZStack(alignment: .topLeading) {
            ForEach(0..<count, id: \.self) { i in
                let y = CGFloat(i) * Self.baseSpacing
                Text("\(i + 1)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VoltraColor.textFaint.opacity(0.85))
                    .position(x: Self.marginStrip - 2, y: y + 6)
            }
            if drawHalf {
                ForEach(0..<count, id: \.self) { i in
                    let y = CGFloat(i) * Self.baseSpacing + Self.baseSpacing / 2
                    Text("\(i + 1).5")
                        .font(.system(size: 7, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.55))
                        .position(x: Self.marginStrip - 2, y: y)
                }
            }
            if drawQuarter {
                ForEach(0..<count, id: \.self) { i in
                    let y25 = CGFloat(i) * Self.baseSpacing + Self.baseSpacing * 0.25
                    let y75 = CGFloat(i) * Self.baseSpacing + Self.baseSpacing * 0.75
                    Text("\(i + 1).25")
                        .font(.system(size: 6, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.45))
                        .position(x: Self.marginStrip - 2, y: y25)
                    Text("\(i + 1).75")
                        .font(.system(size: 6, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.45))
                        .position(x: Self.marginStrip - 2, y: y75)
                }
            }
        }
    }
}

extension View {
    /// Attaches the content-space debug grid layer to the receiver via
    /// `.background(...)`. The layer's frame inherits the receiver's
    /// intrinsic frame, so when the receiver is the inner content
    /// container of a ScrollView the layer covers the full scrollable
    /// content and scrolls with it physically — no preference-key
    /// translation, no named coordinate space.
    ///
    /// The receiver should be the inner `VStack` / `LazyVStack` (or
    /// equivalent) that lives directly inside the ScrollView. Do not
    /// attach to the ScrollView itself — its frame is the viewport,
    /// not the content.
    ///
    /// No-op (cosmetically and behaviorally) when the overlay is off.
    /// Hit-testing is disabled inside the layer; the modifier never
    /// blocks touches.
    ///
    /// Usage:
    /// ```swift
    /// ScrollView {
    ///     VStack {
    ///         …
    ///     }
    ///     .debugGridContentLayer()  // ← here, on the inner stack
    /// }
    /// ```
    func debugGridContentLayer() -> some View {
        background(DebugGridContentLayer())
    }
}

// MARK: - Modifier (viewport-pinned vertical lines + column letters)

private struct DebugGridOverlayModifier: ViewModifier {

    @AppStorage("debugGridMode") private var modeRaw: String =
        DebugGridDensity.off.rawValue

    private var density: DebugGridDensity {
        DebugGridDensity.from(modeRaw)
    }

    func body(content: Content) -> some View {
        content
            // Capture region anchors published by descendants so we can
            // resolve them via the GeometryProxy in the overlay layer
            // (State 4).
            .overlayPreferenceValue(DebugRegionsPreferenceKey.self) { regions in
                if density != .off {
                    GeometryReader { proxy in
                        DebugGridViewportLayer(
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

// MARK: - DebugGridViewportLayer (vertical lines + column letters + regions)

private struct DebugGridViewportLayer: View {

    let density: DebugGridDensity
    let regions: [DebugRegion]
    let proxy: GeometryProxy

    /// 32pt base spacing — locked per V4-D22.
    private static let baseSpacing: CGFloat = 32

    /// Width of the leading row-number strip / height of the top
    /// column-letter strip.
    private static let marginStrip: CGFloat = 14

    var body: some View {
        let safe = proxy.safeAreaInsets
        let w = proxy.size.width
        let h = proxy.size.height

        let stripTop = safe.top + 0

        ZStack(alignment: .topLeading) {
            // 1) Vertical gridlines — VIEWPORT pinned, full height.
            Canvas { ctx, size in
                drawVerticalLines(ctx: &ctx, size: size)
            }
            .frame(width: w, height: h)

            // 2) Column letters across top margin strip — VIEWPORT pinned.
            columnLabels(width: w, stripTop: stripTop)

            // 3) Region overlay (State 4 only) — viewport-resolved anchors.
            if density == .max {
                regionOverlay(proxy: proxy)
            }
        }
        .frame(width: w, height: h)
    }

    // MARK: vertical gridlines

    private func drawVerticalLines(ctx: inout GraphicsContext, size: CGSize) {
        let drawQuarter = (density == .quarter || density == .max)
        let drawHalf = (density == .half || drawQuarter)

        if drawQuarter {
            strokeVerticals(
                ctx: &ctx,
                size: size,
                spacing: Self.baseSpacing / 4,
                lineWidth: 0.3,
                color: VoltraColor.textFaint.opacity(0.14),
                skipMultiplesOf: 2
            )
        }
        if drawHalf {
            strokeVerticals(
                ctx: &ctx,
                size: size,
                spacing: Self.baseSpacing / 2,
                lineWidth: 0.4,
                color: VoltraColor.textFaint.opacity(0.20),
                skipMultiplesOf: 2
            )
        }
        strokeVerticals(
            ctx: &ctx,
            size: size,
            spacing: Self.baseSpacing,
            lineWidth: 0.6,
            color: VoltraColor.textFaint.opacity(0.30),
            skipMultiplesOf: 0
        )
    }

    private func strokeVerticals(
        ctx: inout GraphicsContext,
        size: CGSize,
        spacing: CGFloat,
        lineWidth: CGFloat,
        color: Color,
        skipMultiplesOf: Int
    ) {
        var path = Path()
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
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // MARK: column letters (top margin) — viewport-pinned

    @ViewBuilder
    private func columnLabels(width: CGFloat, stripTop: CGFloat) -> some View {
        let drawHalf = (density == .half || density == .quarter || density == .max)
        let drawQuarter = (density == .quarter || density == .max)

        ZStack(alignment: .topLeading) {
            ForEach(baseColumnIndices(width: width), id: \.self) { i in
                let x = CGFloat(i) * Self.baseSpacing
                Text(columnLetters(for: i))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VoltraColor.textFaint.opacity(0.85))
                    .position(x: x + 6, y: stripTop + 7)
            }
            if drawHalf {
                ForEach(baseColumnIndices(width: width).dropLast(), id: \.self) { i in
                    let x = CGFloat(i) * Self.baseSpacing + Self.baseSpacing / 2
                    Text("\(columnLetters(for: i)).5")
                        .font(.system(size: 7, weight: .regular, design: .monospaced))
                        .foregroundStyle(VoltraColor.textFaint.opacity(0.55))
                        .position(x: x, y: stripTop + 7)
                }
            }
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
    private func columnLetters(for index: Int) -> String {
        var n = index
        var s = ""
        repeat {
            s = String(UnicodeScalar(65 + (n % 26))!) + s
            n = n / 26 - 1
        } while n >= 0
        return s
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
    /// Mounts the viewport-pinned half of the debug grid (vertical lines
    /// + column letters + region overlay). Reads
    /// `@AppStorage("debugGridMode")`; renders nothing when `.off`.
    /// Mounted automatically by `pageBadge(_:)` so most screens get it
    /// for free.
    ///
    /// Pair with `.debugGridContentLayer()` on the inner ScrollView
    /// content container to get the content-space half (horizontal
    /// lines + row labels) that physically scrolls with content.
    /// Screens without scroll content can omit it — they will see only
    /// the vertical grid + column letters, which is correct behavior
    /// for a non-scrolling screen.
    func debugGridOverlay() -> some View {
        modifier(DebugGridOverlayModifier())
    }
}

// MARK: - SUPERSEDED — legacy 9-anchor overlay (b70 V4-D18)
//
// The original four-state anchor overlay (off/corners/midlines/full)
// lived here through b71. Replaced in b72 by the progressive-density
// grid; refined in b73 with a (failed) PreferenceKey-translation path;
// rebuilt in b74 with a true content-space layer. The legacy enum is
// retained — but unmounted — so a rollback is a one-line change in
// `BuildBadgeOverlay.swift`'s tap handler (cycle the legacy enum
// instead) plus restoring the modifier body. Delete after one clean
// ship of b74.

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
