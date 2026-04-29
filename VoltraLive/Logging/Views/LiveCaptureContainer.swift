// LiveCaptureContainer.swift
//
// b53: Wrapper view that selects between LiveCaptureView (V1, the
// production multi-Voltra capture screen) and LiveCaptureViewV2 (the
// b53 single-Voltra clean redesign sourced from the design-studio
// branch). Reads the user's persistent UI choice from @AppStorage,
// and on first launch presents a one-time picker sheet so the user
// can opt into the V2 preview.
//
// Why a container instead of a flag inside LiveCaptureView: V1 owns
// a deeply nested @StateObject WriterRouter graph, set-suggestion
// caches, and chain-flow hooks that are EXPENSIVE to construct on
// every navigation. V2 is a much lighter view. Wrapping with a
// switch keeps both code paths clean and lets the team iterate on
// V2 in isolation without touching V1's behavior \u2014 which is the
// fallback for any session that doesn't fit the V2 single-Voltra
// model (superset chains, dual-Voltra independent mode, etc.).
//
// Routing decisions baked in:
//   - V1 is the default. Even if the user opted into V2, we fall
//     back to V1 whenever the active session has 2+ chain entries
//     OR both Voltras are paired in a non-trivial mode \u2014 V2 is
//     explicitly single-Voltra and would mis-render those flows.
//   - The user's choice persists per-install (not per-session) so
//     once they pick V2 they stay on V2 across launches.

import SwiftUI

/// b53: Storage key for the user's V1/V2 preference. Values:
///   - "v1" \u2192 production multi-Voltra capture screen (default)
///   - "v2" \u2192 single-Voltra preview redesign
///   - missing \u2192 first-launch sheet appears, defaults to V1 on cancel
private let liveCaptureUIVersionKey = "liveCaptureUIVersion"

struct LiveCaptureContainer: View {
    @EnvironmentObject var mdm: MultiDeviceManager
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
    }

    /// Decide whether to render V2. As of b59:
    ///   - V1 still wins for chain/superset sessions (V2 has no chain UI).
    ///   - V2 wins when both Voltras are paired (only dual-aware view).
    ///   - Single-Voltra sessions respect the user's persistent preference.
    private var shouldUseV2: Bool {
        // b59 (fixing a b58 oversight): V2 is now the only view with
        // dual-Voltra-aware chrome (dualHeaderCluster, MERGE button,
        // fused TWIN pill, focusedSlot routing, pulley grey-out in
        // Twin). The previous gate sent the user to V1 the moment
        // both Voltras paired, which silently hid every b58 dual-
        // Voltra change. Confirmed via IMG_2400 (b58 on TestFlight,
        // both Voltras connected, legacy V1 ACTIVE/NEXT header still
        // showing). New rule:
        //   - If a chain/superset entry exists \u2192 V1 (V2 has no
        //     chain UI, that regression matters more than dual UI).
        //   - Else if both Voltras paired \u2192 V2 (only dual-aware view).
        //   - Else \u2192 respect the user's persistent V1/V2 preference.
        let bothPaired = mdm.left.connectionState.isConnected
            && mdm.right.connectionState.isConnected
        let hasChain = !mdm.supersetChain.isEmpty
        if hasChain { return false }
        if bothPaired { return true }
        return uiVersion == "v2"
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
