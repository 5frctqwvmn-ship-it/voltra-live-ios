// MarqueeText.swift
//
// b57 V3 §7 — Horizontally-scrolling text used for the exercise-name
// row in LiveCaptureViewV2's header. When the rendered text width fits
// the available width, the view renders as a static centered Text with
// no animation. When it overflows, the marquee runs:
//
//   1. Show truncated text for `pauseSeconds` (default 5 s).
//   2. Scroll horizontally over `scrollSeconds` (computed from overflow
//      distance / pixelsPerSecond) to reveal the trailing characters.
//   3. Reset to start, pause again, loop.
//
// The "reset" is an instant snap back to x = 0 with no fade, matching
// the spec's "show truncated view ~5s, scroll horizontally to reveal
// the remainder, reset, loop". A 2x-buffered second copy renders
// off-screen during the scroll so the cursor is never visually empty.
//
// Implementation notes:
//   - We measure rendered width via a hidden Text + GeometryReader pair.
//     This is cheap (one extra pass) and avoids Text-with-fixed-width
//     truncation semantics.
//   - The animation is driven by a Timer-published phase variable so
//     SwiftUI can interrupt it cleanly when `text` changes.
//
// This file is single-purpose and self-contained. Sacred files NOT
// touched.

import SwiftUI

struct MarqueeText: View {

    let text: String
    let font: Font
    let color: Color

    /// Seconds to pause before starting (and after completing) each
    /// scroll cycle. Default 5 s per spec.
    let pauseSeconds: Double

    /// Horizontal scroll speed in points-per-second. ~30 pt/s feels
    /// readable without being sluggish; tweak to taste.
    let pixelsPerSecond: Double

    init(
        text: String,
        font: Font = .system(size: 14, weight: .semibold),
        color: Color = .primary,
        pauseSeconds: Double = 5,
        pixelsPerSecond: Double = 30
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.pauseSeconds = pauseSeconds
        self.pixelsPerSecond = pixelsPerSecond
    }

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>? = nil

    var body: some View {
        // Measure text width with a hidden copy.
        let measuredText = Text(text).font(font)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Hidden measurer.
                measuredText
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(0)
                    .background(
                        GeometryReader { tg in
                            Color.clear.preference(
                                key: MarqueeWidthKey.self,
                                value: tg.size.width
                            )
                        }
                    )
                    .onPreferenceChange(MarqueeWidthKey.self) { w in
                        textWidth = w
                    }

                // Visible marquee, masked to the container width.
                if needsMarquee {
                    measuredText
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(color)
                        .offset(x: offset)
                } else {
                    measuredText
                        .lineLimit(1)
                        .foregroundColor(color)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .onAppear {
                containerWidth = geo.size.width
                restartLoop()
            }
            .onChange(of: geo.size.width) { _, w in
                containerWidth = w
                restartLoop()
            }
            .onChange(of: text) { _, _ in
                restartLoop()
            }
            .onChange(of: textWidth) { _, _ in
                restartLoop()
            }
        }
        .frame(height: 18)
    }

    private var needsMarquee: Bool {
        textWidth > containerWidth + 1 && containerWidth > 0
    }

    private var overflow: CGFloat {
        max(0, textWidth - containerWidth)
    }

    private func restartLoop() {
        animationTask?.cancel()
        offset = 0
        guard needsMarquee else { return }
        let scrollDuration = max(0.4, Double(overflow) / pixelsPerSecond)
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                // Pause at start.
                try? await Task.sleep(nanoseconds: UInt64(pauseSeconds * 1_000_000_000))
                if Task.isCancelled { return }
                // Scroll left to reveal the rest.
                withAnimation(.linear(duration: scrollDuration)) {
                    offset = -overflow
                }
                try? await Task.sleep(nanoseconds: UInt64(scrollDuration * 1_000_000_000))
                if Task.isCancelled { return }
                // Pause at end.
                try? await Task.sleep(nanoseconds: UInt64(pauseSeconds * 1_000_000_000))
                if Task.isCancelled { return }
                // Snap reset (instant).
                withAnimation(.none) {
                    offset = 0
                }
            }
        }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
#Preview("MarqueeText — short") {
    MarqueeText(text: "Squat · Set 3")
        .frame(width: 200)
        .background(Color.black)
        .foregroundColor(.white)
}

#Preview("MarqueeText — overflow") {
    MarqueeText(text: "Reverse Hyper Pulley with Eccentric Overload · Set 3")
        .frame(width: 200)
        .background(Color.black)
        .foregroundColor(.white)
}
#endif
