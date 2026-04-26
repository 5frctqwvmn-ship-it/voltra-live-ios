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

    @State private var pickedDayType: DayType? = nil
    @State private var customLabel: String = ""
    @State private var showingCustom = false
    @State private var showingDashboard = false
    @State private var showingDebug = false

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
                        }
                        .padding(.horizontal, 18)

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
            .sheet(isPresented: $showingCustom) {
                customSheet
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

    private var connectionPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ble.connectionState.isConnected ? VoltraColor.accent : VoltraColor.textFaint)
                .frame(width: 8, height: 8)
                .shadow(color: ble.connectionState.isConnected ? VoltraColor.accent : .clear,
                        radius: 4)
            Text(ble.connectionState.isConnected ? "Connected" : "Not connected")
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
            customLabel = ""
            showingCustom = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: DayType.custom.symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(VoltraColor.textDim)
                Spacer(minLength: 0)
                Text("CUSTOM")
                    .font(.system(size: 15, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(VoltraColor.text)
                Text("Name your own day")
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

    // MARK: - Custom day sheet

    private var customSheet: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Name your day")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(VoltraColor.text)
                    TextField("e.g. Push, Pull, Mobility", text: $customLabel)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(VoltraColor.bgElev2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(VoltraColor.text)
                    Button {
                        let label = customLabel.trimmingCharacters(in: .whitespaces)
                        guard !label.isEmpty else { return }
                        logging.startSession(dayType: .custom, customLabel: label)
                        showingCustom = false
                        pickedDayType = .custom
                    } label: {
                        Text("Start")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(VoltraColor.accent)
                            .foregroundColor(VoltraColor.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Custom Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCustom = false }
                        .foregroundColor(VoltraColor.textDim)
                }
            }
        }
        .presentationDetents([.medium])
        .buildBadgeOverlay()
    }
}

#Preview {
    LoggingHomeView()
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
        .environmentObject(LoggingStore())
}
