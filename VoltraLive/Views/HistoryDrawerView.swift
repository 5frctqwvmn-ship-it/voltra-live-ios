// HistoryDrawerView.swift
// Sheet showing current session sets, past sessions list, End Session, Clear All buttons.
// Also shows BLE log entries for debugging.

import SwiftUI
import SwiftData

struct HistoryDrawerView: View {
    @EnvironmentObject var ble: VoltraBLEManager
    @EnvironmentObject var session: SessionStore
    @Binding var isPresented: Bool

    @State private var showClearConfirm = false
    @State private var pastSessions: [PastSession] = []

    var body: some View {
        NavigationView {
            ZStack {
                VoltraColor.bgElev.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // MARK: Current session sets
                        sectionHeader("THIS SESSION")
                        if session.completedSets.isEmpty {
                            emptyMsg("No sets yet this session.")
                        } else {
                            VStack(spacing: 6) {
                                ForEach(Array(session.completedSets.enumerated()), id: \.offset) { idx, set in
                                    HStack {
                                        Text("Set \(idx + 1)")
                                            .foregroundColor(VoltraColor.textDim)
                                        Spacer()
                                        Text("\(set.reps) reps · peak \(String(format: "%.1f", set.peakLb)) lb")
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(VoltraColor.text)
                                    }
                                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                                    .background(VoltraColor.bgElev2)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .font(.system(size: 13))
                                }
                            }
                            .padding(.bottom, 8)
                        }

                        // MARK: Action buttons
                        HStack(spacing: 10) {
                            Button("End Session") {
                                session.endSession()
                                pastSessions = session.fetchPastSessions()
                            }
                            .buttonStyle(SecondaryButtonStyle())

                            Button("Clear All") {
                                showClearConfirm = true
                            }
                            .buttonStyle(DangerButtonStyle())
                        }
                        .padding(.bottom, 20)

                        // MARK: Past sessions
                        sectionHeader("PAST SESSIONS")
                        if pastSessions.isEmpty {
                            emptyMsg("No past sessions yet.")
                        } else {
                            VStack(spacing: 6) {
                                ForEach(pastSessions.prefix(10)) { s in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(s.formattedDate)
                                            .foregroundColor(VoltraColor.text)
                                        Text("\(s.sets.count) sets · \(s.totalReps) reps · peak \(String(format: "%.1f", s.peakForceLb)) lb")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(VoltraColor.textDim)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                                    .background(VoltraColor.bgElev2)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .font(.system(size: 13))
                                }
                            }
                            .padding(.bottom, 8)
                        }

                        // MARK: BLE log
                        sectionHeader("BLE LOG")
                        ScrollView {
                            Text(logText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(VoltraColor.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(maxHeight: 200)
                        .background(VoltraColor.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(VoltraColor.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(EdgeInsets(top: 16, leading: 20, bottom: 32, trailing: 20))
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                        .foregroundColor(VoltraColor.accent)
                }
            }
        }
        .onAppear {
            pastSessions = session.fetchPastSessions()
        }
        .alert("Clear all sessions?", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) {
                session.clearAll()
                pastSessions = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all saved sessions and reset the current session.")
        }
        .preferredColorScheme(.dark)
    }

    private var logText: String {
        ble.log.suffix(30)
            .map { "[\($0.formattedTime)] \($0.message)" }
            .joined(separator: "\n")
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .kerning(1.5)
            .foregroundColor(VoltraColor.textDim)
            .textCase(.uppercase)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }

    private func emptyMsg(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(VoltraColor.textFaint)
            .padding(.bottom, 8)
    }
}

// MARK: - Button styles

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(VoltraColor.text)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(VoltraColor.bgElev2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(VoltraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(VoltraColor.danger)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(VoltraColor.danger, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    HistoryDrawerView(isPresented: .constant(true))
        .environmentObject(VoltraBLEManager())
        .environmentObject(SessionStore())
}
