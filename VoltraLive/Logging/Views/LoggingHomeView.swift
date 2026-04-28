// LoggingHomeView.swift
// Home screen for the logging flow — shown after a Voltra connects (or any
// time the user wants to start a workout). Four day-type tiles plus Custom.
//
// User scope (verbatim): "I've got a series of options like backday, chest day,
// leg day, arm day, and from there there's a submenu that talks about the
// various exercises that I've already logged, and then an ability to create
// a new one."

import SwiftUI

struct LoggingHomeView: View {

    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var logging: LoggingStore
    @EnvironmentObject var demo: DemoController
    /// Build 35: HealthKit access for the home-screen status chip. Lets
    /// the user see at a glance whether HK has been asked for permission
    /// and tap to re-prompt if it never appeared.
    @EnvironmentObject var health: HealthKitStore
    /// Build 40: dual-Voltra status feeds the connection pill so we can
    /// show "Left + Right" when both are paired via the unified Connect
    /// sheet. Selection of which Voltra is active for a workout still
    /// happens pre-workout (b42), so this chip is purely informational.
    @EnvironmentObject var mdm: MultiDeviceManager

    @State private var pickedDayType: DayType? = nil
    @State private var customLabel: String = ""
    /// Build 30: inline custom-day expander. Replaces the prior modal sheet —
    /// tapping the Custom tile expands a textfield + recent-labels chip row
    /// directly below the grid, no extra navigation.
    @State private var showingCustomInline = false
    /// Build 31: GROUP picker on the inline custom card. Defaults to .custom
    /// so the existing zero-friction flow (just type and Start) is unchanged.
    /// User can tap the dropdown to roll the workout under one of the four
    /// preset groups for home-screen tile grouping.
    @State private var pickedGroup: DayType = .custom
    @State private var showingDashboard = false
    @State private var showingDebug = false
    @FocusState private var customFieldFocused: Bool

    private let primaryDayTypes: [DayType] = [.leg, .back, .chest, .arm]

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        header

                        VStack(spacing: 14) {
                            Text("PICK A DAY")
                                .font(VoltraFont.label())
                                .kerning(2)
                                .foregroundColor(VoltraColor.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(primaryDayTypes) { dt in
                                    dayTile(dt)
                                }
                                customTile
                            }

                            // Build 30: inline custom-day expander, shown
                            // directly below the grid when the Custom tile is
                            // tapped. One tap + typing (or one tap on a
                            // recent chip) starts a session — no sheet hop.
                            if showingCustomInline {
                                inlineCustomCard
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, 18)
                        .animation(.easeInOut(duration: 0.18), value: showingCustomInline)

                        // Live dashboard shortcut — keeps v0.1 functionality reachable.
                        Button {
                            showingDashboard = true
                        } label: {
                            HStack {
                                Image(systemName: "waveform.path.ecg")
                                Text("Open live dashboard")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(VoltraColor.textDim)
                            }
                            .foregroundColor(VoltraColor.text)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(VoltraColor.bgElev)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(VoltraColor.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 18)

                        // v0.4.6.3: post-pair Demo Mode entry. Real device
                        // stays paired and telemetry flows from it; we just
                        // don't persist the session.
                        if !demo.isActive {
                            HStack {
                                Spacer()
                                DemoModeButton(source: .postPair) {
                                    guard let handler = DemoTelemetryBridge.shared.handler else { return }
                                    demo.note(.buttonTap(label: "Demo Mode (post-pair)", screen: "LoggingHome"))
                                    demo.enter(source: .postPair, onTelemetry: handler)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.top, 14)
                }
            }
            .navigationDestination(item: $pickedDayType) { dt in
                ExercisePickerView(dayType: dt)
            }
            // After the user finishes a session and dismisses the export
            // sheet, LiveCaptureView bumps logging.sessionExitTick. Pop the
            // entire navigation stack back to root here so the user lands on
            // the day-picker home and isn't stranded on a stale capture view.
            .onChange(of: logging.sessionExitTick) { _, _ in
                pickedDayType = nil
            }
            .navigationDestination(isPresented: $showingDashboard) {
                DashboardView()
            }
            .sheet(isPresented: $showingDebug) {
                DebugView()
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(VoltraColor.accent)
                        .font(.system(size: 22, weight: .bold))
                    Text("VOLTRA")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    Text("Live")
                        .font(.system(size: 18))
                        .foregroundColor(VoltraColor.textDim)
                    // Inline build chip removed in v0.3.4 — the global
                    // BuildBadgeOverlay (bottom-trailing on every screen)
                    // covers this case more consistently.
                }
                Spacer()
                healthPill
                connectionPill
                Button {
                    showingDebug = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(VoltraColor.textDim)
                        .padding(8)
                        .background(VoltraColor.bgElev)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Text("Pick a day to start logging.")
                .font(.system(size: 15))
                .foregroundColor(VoltraColor.textDim)
        }
        .padding(.horizontal, 18)
    }

    /// Build 35: tappable HealthKit status chip. Apple deliberately hides
    /// READ-permission status, so we surface the next-best proxies:
    ///   - red dot  = HealthKit unavailable on device
    ///   - amber    = available but never prompted yet (tap to prompt)
    ///   - blue     = prompted but no live samples seen yet
    ///   - green    = receiving live samples (last < 30s)
    /// Tapping ALWAYS calls requestAuthIfNeeded() so the user can
    /// recover if the system sheet never appeared the first time.
    private var healthPill: some View {
        let now = Date()
        let fresh: Bool = {
            guard let t = health.lastHRSampleAt else { return false }
            return now.timeIntervalSince(t) < 30
        }()
        let (dotColor, label): (Color, String) = {
            if !health.isAvailable { return (VoltraColor.textFaint, "HK n/a") }
            if !health.hasRequestedAuthorization { return (.orange, "HK ask") }
            if fresh { return (VoltraColor.accent, "HK live") }
            return (.blue, "HK on")
        }()
        return Button {
            health.requestAuthIfNeeded()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.7), radius: 4)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(VoltraColor.textDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(VoltraColor.bgElev)
            .overlay(
                Capsule().stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Build 40: dual-aware connection pill.
    ///
    /// Priority for the label:
    ///   1. If MultiDeviceManager has BOTH slots connected -> "Left + Right".
    ///   2. If only one MDM slot is connected             -> "Left" or "Right".
    ///   3. Else fall back to the legacy single-device manager:
    ///        connected     -> "Connected"
    ///        anything else -> "Not connected"
    /// The dot is green whenever ANY of the above is connected.
    private var connectionPill: some View {
        let leftPaired  = mdm.left.connectionState.isConnected
        let rightPaired = mdm.right.connectionState.isConnected
        let blePaired   = ble.connectionState.isConnected
        let anyConnected = leftPaired || rightPaired || blePaired
        let label: String = {
            if leftPaired && rightPaired { return "Left + Right" }
            if leftPaired  { return "Left connected" }
            if rightPaired { return "Right connected" }
            if blePaired   { return "Connected" }
            return "Not connected"
        }()
        return HStack(spacing: 6) {
            Circle()
                .fill(anyConnected ? VoltraColor.accent : VoltraColor.textFaint)
                .frame(width: 8, height: 8)
                .shadow(color: anyConnected ? VoltraColor.accent : .clear,
                        radius: 4)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(VoltraColor.textDim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(VoltraColor.bgElev)
        .overlay(
            Capsule().stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    // MARK: - Tiles

    private func dayTile(_ dt: DayType) -> some View {
        Button {
            logging.startSession(dayType: dt)
            pickedDayType = dt
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: dt.symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(VoltraColor.accent)
                Spacer(minLength: 0)
                Text(dt.displayName.uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.text)
                Text("Tap to start")
                    .font(.system(size: 12))
                    .foregroundColor(VoltraColor.textDim)
            }
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var customTile: some View {
        Button {
            // Toggle: tapping the tile while the inline expander is open
            // collapses it, mirroring the classic disclosure pattern.
            if showingCustomInline {
                showingCustomInline = false
                customFieldFocused = false
            } else {
                customLabel = ""
                showingCustomInline = true
                // Defer focus to the next runloop tick — SwiftUI needs the
                // TextField to be in the hierarchy before focus takes.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    customFieldFocused = true
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: DayType.custom.symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(showingCustomInline ? VoltraColor.accent : VoltraColor.textDim)
                Spacer(minLength: 0)
                Text("CUSTOM")
                    .font(.system(size: 15, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.text)
                Text(showingCustomInline ? "Tap again to collapse" : "Name your own day")
                    .font(.system(size: 12))
                    .foregroundColor(VoltraColor.textDim)
            }
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(VoltraColor.bgElev)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VoltraColor.border.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline custom-day card (build 30)

    /// Inline expansion shown directly below the day-tile grid when the user
    /// taps Custom. Replaces the prior modal sheet so that creating a
    /// custom-named day is one tap + typing instead of tap → modal → typing
    /// → Start. Recent custom labels are surfaced as one-tap chips so repeat
    /// workouts ("Push", "Mobility") need zero typing.
    private var inlineCustomCard: some View {
        let recents = logging.recentCustomLabels()
        let trimmed = customLabel.trimmingCharacters(in: .whitespaces)
        let canStart = !trimmed.isEmpty

        return VStack(alignment: .leading, spacing: 14) {
            // Build 31: GROUP picker. The user asked for a dropdown that
            // lets them tag the custom workout under one of the four
            // preset groups (Leg / Back / Chest / Arm) or keep it as a
            // freestanding Custom day. The chosen group becomes the
            // session's dayType so history can roll the workout up under
            // that preset's tile on the home screen.
            Text("GROUP")
                .font(VoltraFont.label())
                .kerning(2)
                .foregroundColor(VoltraColor.textDim)

            Menu {
                ForEach(DayType.allCases) { dt in
                    Button {
                        pickedGroup = dt
                    } label: {
                        if pickedGroup == dt {
                            Label(dt.displayName, systemImage: "checkmark")
                        } else {
                            Text(dt.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(pickedGroup.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(VoltraColor.text)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(VoltraColor.textDim)
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                .background(VoltraColor.bgElev2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("NAME YOUR DAY")
                .font(VoltraFont.label())
                .kerning(2)
                .foregroundColor(VoltraColor.textDim)
                .padding(.top, 4)

            HStack(spacing: 10) {
                TextField("e.g. Push, Pull, Mobility", text: $customLabel)
                    .textFieldStyle(.plain)
                    .focused($customFieldFocused)
                    .submitLabel(.go)
                    .onSubmit { startCustom(trimmed) }
                    .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                    .background(VoltraColor.bgElev2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(VoltraColor.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundColor(VoltraColor.text)

                Button {
                    startCustom(trimmed)
                } label: {
                    Text("Start")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(canStart ? VoltraColor.accent : VoltraColor.bgElev2)
                        .foregroundColor(canStart ? VoltraColor.bg : VoltraColor.textFaint)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canStart)
                .buttonStyle(.plain)
            }

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1)
                        .foregroundColor(VoltraColor.textDim)
                    // Wrapping chip row — LazyVGrid with adaptive sizing
                    // gives free reflow without manual width math.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(recents, id: \.self) { label in
                            recentChip(label)
                        }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltraColor.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VoltraColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func recentChip(_ label: String) -> some View {
        Button {
            // One-tap-start when picking a recent label — the user has
            // already named this day before, no reason to make them confirm.
            startCustom(label)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundColor(VoltraColor.text)
                .background(VoltraColor.bgElev2)
                .overlay(
                    Capsule().stroke(VoltraColor.border, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func startCustom(_ rawLabel: String) {
        let label = rawLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        // Build 31: use the picked group as the session's dayType. The
        // free-form name is stored as customLabel so the home tile can
        // display "Push" under the Chest group, etc. If the user kept the
        // group as Custom, behavior matches build 30 exactly.
        logging.startSession(dayType: pickedGroup, customLabel: label)
        showingCustomInline = false
        customFieldFocused = false
        pickedDayType = pickedGroup
    }
}

#Preview {
    LoggingHomeView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
        .environmentObject(LoggingStore())
        .environmentObject(DemoController())
        .environmentObject(HealthKitStore())
        .environmentObject(MultiDeviceManager())
}
