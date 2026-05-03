// LiveCaptureContainer.swift
//
// b53: Wrapper view that selects between LiveCaptureView (V1, the
// production multi-Voltra capture screen) and LiveCaptureViewV2 (the
// b53 single-Voltra clean redesign sourced from the design-studio
// branch).
//
// b71 (V4-D21 part 3 / Step 3): V2 is now the canonical live capture
// view for ALL session shapes — single-Voltra, dual-Voltra, AND
// superset chains. The pre-b71 routing rules
//   - hasChain → V1
//   - bothPaired → V2
//   - else → user's persistent preference
// are deprecated. The new policy is V2-by-default with V1 surfaced
// only via an emergency kill switch.
//
// Why a container instead of a flag inside LiveCaptureView: V1 owns
// a deeply nested @StateObject WriterRouter graph, set-suggestion
// caches, and chain-flow hooks that are EXPENSIVE to construct on
// every navigation. V2 is a much lighter view. Wrapping with a
// switch keeps both code paths clean and lets us keep V1 on disk
// as a verbatim rollback artifact without paying its construction
// cost on every nav.
//
// Routing decisions baked in (b71):
//   - V2 is the default for every session shape. Below-chart parity
//     (V4-D21 part 1) and chain UI parity (V4-D21 part 2) closed the
//     pre-b71 gaps that previously forced V1 fallback.
//   - The `@AppStorage("liveCaptureUIVersion")` value is now an
//     EMERGENCY KILL SWITCH only. Set to "v1" via a debug build or
//     a future Settings toggle to revert a single install if a V2
//     regression is discovered in the field. Default ("" or "v2")
//     routes to V2.
//   - The first-launch picker sheet still appears once per install
//     to record the user's choice, but both choices now end up on
//     V2 unless the user explicitly picks V1 — the picker copy is
//     updated accordingly.

import SwiftUI

/// b53: Storage key for the user's V1/V2 preference.
///
/// b71 (V4-D21 part 3): semantics inverted. This key is now an
/// EMERGENCY KILL SWITCH for V1 fallback, not a feature opt-in.
/// Values:
///   - "v1" \u2192 emergency rollback to V1 (only set if a V2
///              regression is discovered in production)
///   - "v2" \u2192 explicit V2 (the default route anyway)
///   - missing / empty \u2192 V2 (canonical)
private let liveCaptureUIVersionKey = "liveCaptureUIVersion"

struct LiveCaptureContainer: View {
    // b71 (V4-D21 part 3): `mdm` is no longer read here — the routing
    // predicate collapsed to a single AppStorage check — but the
    // environment object is still injected by the app entry for
    // both V1 and V2 to consume. We do not need to re-declare it on
    // this container.
    @AppStorage(liveCaptureUIVersionKey) private var uiVersion: String = ""

    /// True until the user has made a choice for this install. Drives
    /// the one-time intro sheet.
    @State private var showingFirstLaunchPicker: Bool = false

    var body: some View {
        Group {
            if shouldUseV2 {
                LiveCaptureViewV2()
            } else {
                LiveCaptureView()
            }
        }
        .onAppear {
            if uiVersion.isEmpty {
                showingFirstLaunchPicker = true
            }
        }
        .sheet(isPresented: $showingFirstLaunchPicker) {
            LiveCaptureUIPickerSheet(
                onChoose: { choice in
                    uiVersion = choice
                    showingFirstLaunchPicker = false
                }
            )
            .interactiveDismissDisabled(false)
        }
        // b66 V4.2: page-name badge.
        .pageBadge("LiveCaptureContainer")
        // B74-F11: recorder screen tag.
        .recorderScreen("LiveCaptureContainer")
        }

    /// Decide whether to render V2. As of b71 (V4-D21 part 3): V2 is
    /// the canonical view for every session shape; V1 only renders
    /// when the user has explicitly set the `liveCaptureUIVersion`
    /// kill switch to `"v1"`.
    private var shouldUseV2: Bool {
        // b71 (V4-D21 part 3 / Step 3): the pre-b71 conditional
        // routing
        //     if hasChain { return false }
        //     if bothPaired { return true }
        //     return uiVersion == "v2"
        // is removed. V4-D21 parts 1 and 2 closed the V2 parity
        // gaps (below-chart UI; chain UI + SWAP semantics + lifecycle
        // hooks), so V2 now handles every session shape V1 does
        // — single-Voltra, dual-Voltra Independent / Combined, and
        // superset chains — with identical user-visible behavior.
        //
        // Routing collapses to: V2 unless the kill switch says V1.
        // The default value of `uiVersion` is the empty string, which
        // routes to V2.
        return uiVersion != "v1"
    }
}

// MARK: - First-launch picker sheet

/// b53: One-time sheet shown the first time the user lands on the
/// live capture screen after upgrading to b53. Lets them choose
/// between the production V1 UI and the V2 preview. The choice is
/// persistent (per install) but reversible from Settings (TODO:
/// b54 \u2014 add a Settings toggle to re-pick).
struct LiveCaptureUIPickerSheet: View {
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PICK YOUR LIVE SCREEN")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.6)
                            .foregroundColor(VoltraColor.accent)
                        Text("V2 is a preview of the new single-Voltra capture screen. You can switch back any time from Settings.")
                            .font(.system(size: 14))
                            .foregroundColor(VoltraColor.textDim)
                            .fixedSize(horizontal: false, vertical: true)

                        choiceCard(
                            id: "v1",
                            title: "V1 \u{00B7} Default",
                            subtitle: "Production capture screen. Supports superset chains, dual-Voltra independent mode, drop-set cascades, and every feature shipped through b52.",
                            recommended: true
                        )
                        choiceCard(
                            id: "v2",
                            title: "V2 \u{00B7} Preview",
                            subtitle: "Single-Voltra redesign with the new design-system tokens. Falls back to V1 automatically if you pair a second Voltra or build a superset chain.",
                            recommended: false
                        )
                        Spacer(minLength: 8)
                        Text("Default: V1. Tap Use V1 to keep the current screen.")
                            .font(.system(size: 12))
                            .foregroundColor(VoltraColor.textFaint)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Live Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Use V1") { onChoose("v1") }
                        .foregroundColor(VoltraColor.accent)
                }
            }
        }
    }

    private func choiceCard(id: String, title: String, subtitle: String, recommended: Bool) -> some View {
        Button {
            onChoose(id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(VoltraColor.text)
                    Spacer()
                    if recommended {
                        Text("RECOMMENDED")
                            .font(.system(size: 9, weight: .bold))
                            .kerning(1.2)
                            .foregroundColor(VoltraColor.bg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(VoltraColor.accent)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(VoltraColor.textDim)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(recommended ? VoltraColor.accent.opacity(0.5) : VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
