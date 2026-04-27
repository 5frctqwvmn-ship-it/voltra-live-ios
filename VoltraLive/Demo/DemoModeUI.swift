// DemoModeUI.swift
// v0.4.6.3 / build 26
//
// SwiftUI surfaces for Demo Mode:
//   • DemoBanner — sticky, top-of-screen "DEMO MODE — nothing is recorded
//     · build N" indicator. Tapping it exits demo and presents the
//     post-session upload sheet.
//   • DemoModeButton — the secondary text-styled button that appears below
//     the pair card on ConnectView and inside LoggingHomeView.
//   • DemoEndSheet — bottom sheet shown on exit with the trace summary,
//     a free-form "what happened?" textbox, and Send / Discard actions.
//   • DemoModeOverlay view-modifier — applies the banner globally.
//
// All copy is short and neutral — the target user is the dev/debugger, not
// a marketing audience.

import SwiftUI

// MARK: - Banner

struct DemoBanner: View {
    @EnvironmentObject var demo: DemoController
    @Binding var showEndSheet: Bool

    private var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
    }

    var body: some View {
        if demo.isActive {
            Button {
                demo.note(.buttonTap(label: "Exit (banner)", screen: "Banner"))
                showEndSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("DEMO MODE")
                        .font(.system(size: 12, weight: .bold))
                    Text("nothing is recorded · build \(build)")
                        .font(.system(size: 12, weight: .regular))
                        .opacity(0.8)
                    Spacer(minLength: 0)
                    Text("Exit")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.95)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(VoltraColor.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Demo Mode active. Tap to exit.")
        }
    }
}

// MARK: - Entry button (secondary text style)

struct DemoModeButton: View {
    let source: DemoEntrySource
    @EnvironmentObject var demo: DemoController
    let onEntered: () -> Void

    var body: some View {
        Button {
            // Caller wires up the synthetic-or-real telemetry handler in
            // VoltraLiveApp; here we just fire the entry callback.
            onEntered()
        } label: {
            Text("Demo Mode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(VoltraColor.accent)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(VoltraColor.accent.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(demo.isActive ? 0.4 : 1.0)
        .disabled(demo.isActive)
        .accessibilityLabel(source == .prePair
            ? "Enter Demo Mode without pairing"
            : "Enter Demo Mode with paired device")
    }
}

// MARK: - End-of-session upload sheet

struct DemoEndSheet: View {
    let trace: DemoTraceLogger
    @StateObject private var uploader = DemoTraceUploader()
    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Summary card -------------------------------------
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session ended")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(VoltraColor.text)
                        Text("Build \(trace.header.appShort) (\(trace.header.appBuild)) · entry \(trace.header.entrySource)")
                            .font(.system(size: 13))
                            .foregroundColor(VoltraColor.textDim)
                        Text("\(trace.totalEvents) events · \(trace.records.count) records")
                            .font(.system(size: 13))
                            .foregroundColor(VoltraColor.textDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(VoltraColor.bgElev)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // What happened? -----------------------------------
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What happened? (optional)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VoltraColor.textDim)
                        TextEditor(text: $note)
                            .font(.system(size: 14))
                            .foregroundColor(VoltraColor.text)
                            .scrollContentBackground(.hidden)
                            .background(VoltraColor.bgElev)
                            .frame(minHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(VoltraColor.border, lineWidth: 1)
                            )
                    }

                    // Actions ------------------------------------------
                    if let issueURL = uploader.lastIssueURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trace uploaded.")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(VoltraColor.accent)
                            Link("View issue", destination: issueURL)
                                .font(.system(size: 13))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(VoltraColor.bgElev)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if let err = uploader.lastError {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(VoltraColor.warn)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(VoltraColor.bgElev)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Discard")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(VoltraColor.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(VoltraColor.bgElev)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(VoltraColor.border, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await uploader.upload(trace, note: note) }
                        } label: {
                            HStack(spacing: 8) {
                                if uploader.inFlight {
                                    ProgressView().tint(.black).scaleEffect(0.8)
                                }
                                Text(uploader.inFlight ? "Sending…" : "Send to Developer")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(VoltraColor.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(uploader.inFlight || uploader.lastIssueURL != nil)
                    }
                }
                .padding(20)
            }
            .background(VoltraColor.bg.ignoresSafeArea())
            .navigationTitle("Demo Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Global overlay modifier

struct DemoModeOverlay: ViewModifier {
    @EnvironmentObject var demo: DemoController
    @State private var endSheetTrace: DemoTraceLogger? = nil

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            DemoBanner(showEndSheet: Binding(
                get: { false },
                set: { newVal in
                    if newVal {
                        // User tapped the banner: exit demo, capture
                        // finalized trace, present sheet.
                        if let trace = demo.exit() {
                            endSheetTrace = trace
                        }
                    }
                }
            ))
            content
        }
        .sheet(item: $endSheetTrace) { trace in
            DemoEndSheet(trace: trace)
        }
    }
}

extension View {
    /// Applies the sticky DEMO MODE banner globally and presents the
    /// upload sheet on banner tap.
    func demoModeOverlay() -> some View { modifier(DemoModeOverlay()) }
}

// DemoTraceLogger needs to be Identifiable for `.sheet(item:)`. We
// extend it here to keep the trace file focused on its core duty.
extension DemoTraceLogger: Identifiable {
    var id: String { header.startedAtIso }
}
