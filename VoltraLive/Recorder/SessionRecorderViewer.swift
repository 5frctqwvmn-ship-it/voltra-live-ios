// SessionRecorderViewer.swift
// B74-F11 Session Recorder — long-press sheet.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "Toggle" + "Export".
//
// Renders the in-memory event timeline with category filter chips and
// a `ShareLink` that exports BOTH the `.txt` AI-readable report AND
// the `.json` structured envelope in one share action. Files are
// written to the temp directory and handed to ShareLink as URLs so
// the system share sheet can pick destinations natively.
//
// All chrome is dark-themed to match VoltraColor.

import SwiftUI

struct SessionRecorderViewer: View {

    @EnvironmentObject private var recorder: SessionRecorder
    @Environment(\.dismiss) private var dismiss

    @State private var events: [RecorderEvent] = []
    @State private var selectedCategory: RecorderCategory? = nil
    @State private var sharePayload: SharePayload? = nil
    @State private var isReloading: Bool = false

    private struct SharePayload: Equatable {
        let txtURL: URL
        let jsonURL: URL
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VoltraColor.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    filterBar
                    Divider().background(VoltraColor.border)
                    eventList
                }
            }
            .navigationTitle("Session Recorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(VoltraColor.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await reload() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isReloading)
                        .foregroundColor(VoltraColor.accent)

                        shareButton
                    }
                }
            }
            .task { await reload() }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Header (recording state + count)

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(recorder.isRecording ? Color.red : VoltraColor.textFaint)
                .frame(width: 8, height: 8)
            Text(recorder.isRecording ? "RECORDING" : "IDLE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(recorder.isRecording ? Color.red : VoltraColor.textDim)
            Spacer()
            Text("\(events.count) events")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(VoltraColor.textFaint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: Filter chips

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "all", category: nil)
                ForEach(RecorderCategory.allCases, id: \.self) { cat in
                    filterChip(label: cat.rawValue, category: cat)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func filterChip(label: String, category: RecorderCategory?) -> some View {
        let selected = selectedCategory == category
        return Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(selected
                               ? VoltraColor.accent.opacity(0.25)
                               : Color.black.opacity(0.3))
            )
            .overlay(
                Capsule().stroke(selected ? VoltraColor.accent : VoltraColor.border,
                                 lineWidth: 0.5)
            )
            .foregroundColor(selected ? VoltraColor.accent : VoltraColor.textDim)
            .contentShape(Capsule())
            .onTapGesture { selectedCategory = category }
    }

    // MARK: Event list

    private var filteredEvents: [RecorderEvent] {
        let reversed = Array(events.reversed())  // newest first
        guard let cat = selectedCategory else { return reversed }
        return reversed.filter { $0.category == cat }
    }

    private var eventList: some View {
        Group {
            if filteredEvents.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredEvents, id: \.id) { event in
                        eventRow(event)
                            .listRowBackground(VoltraColor.bgElev)
                            .listRowSeparatorTint(VoltraColor.border)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(VoltraColor.bg)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(events.isEmpty
                 ? "No events recorded yet.\nTap the dot to start recording."
                 : "No events match the current filter.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(VoltraColor.textFaint)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VoltraColor.bg)
    }

    @ViewBuilder
    private func eventRow(_ event: RecorderEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(formatTime(event.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(VoltraColor.textFaint)
                Text(event.category.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(categoryColor(event.category).opacity(0.2)))
                    .foregroundColor(categoryColor(event.category))
                if let s = event.screen {
                    Text(s)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(VoltraColor.textFaint)
                }
                if event.actionId != nil {
                    Text("⛓")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(VoltraColor.transition)
                }
            }
            Text(event.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(VoltraColor.text)
            if !event.metadata.isEmpty {
                Text(metadataPreview(event.metadata))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VoltraColor.textDim)
                    .lineLimit(2)
            }
            if let err = event.error {
                Text("err \(err.domain):\(err.code) \(err.message)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VoltraColor.danger)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Toolbar — Share

    @ViewBuilder
    private var shareButton: some View {
        if let payload = sharePayload {
            ShareLink(items: [payload.txtURL, payload.jsonURL]) {
                Image(systemName: "square.and.arrow.up")
            }
            .foregroundColor(VoltraColor.accent)
        } else {
            Button {
                Task { await prepareShare() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .foregroundColor(VoltraColor.textFaint)
        }
    }

    // MARK: Loading + share prep

    private func reload() async {
        isReloading = true
        let snap = await recorder.snapshot()
        events = snap
        await prepareShare()
        isReloading = false
    }

    private func prepareShare() async {
        do {
            let (txt, json) = try await recorder.currentExport()
            let dir = FileManager.default.temporaryDirectory
            let stamp = filenameStamp(from: Date())
            let txtURL  = dir.appendingPathComponent("voltra-recorder-\(stamp).txt")
            let jsonURL = dir.appendingPathComponent("voltra-recorder-\(stamp).json")
            if let data = txt.data(using: .utf8) {
                try data.write(to: txtURL, options: .atomic)
            }
            try json.write(to: jsonURL, options: .atomic)
            sharePayload = SharePayload(txtURL: txtURL, jsonURL: jsonURL)
        } catch {
            // Best-effort; if export fails, the share button stays in
            // the placeholder state and the user can hit reload to
            // retry.
        }
    }

    // MARK: Formatters

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: d)
    }

    private func filenameStamp(from d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: d)
    }

    private func metadataPreview(_ md: [String: RecorderValue]) -> String {
        md.sorted { $0.key < $1.key }
          .prefix(4)
          .map { "\($0.key)=\(describe($0.value))" }
          .joined(separator: " ")
    }

    private func describe(_ v: RecorderValue) -> String {
        switch v {
        case .string(let s): return "\"\(s)\""
        case .int(let i):    return String(i)
        case .double(let d): return String(d)
        case .bool(let b):   return String(b)
        case .hex(let h):    return "hex:\(h)"
        }
    }

    private func categoryColor(_ c: RecorderCategory) -> Color {
        switch c {
        case .ui:        return VoltraColor.accent
        case .nav:       return VoltraColor.transition
        case .state:     return VoltraColor.textDim
        case .async:     return VoltraColor.returnPhase
        case .ble:       return VoltraColor.pull
        case .`guard`:   return VoltraColor.warn
        case .lifecycle: return VoltraColor.textDim
        case .recorder:  return VoltraColor.danger
        }
    }
}
