// View+RecorderScreen.swift
// B74-F11 Session Recorder — `.recorderScreen("Name")` view modifier.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "UI Mount" / "Instrumentation
// Scope" — screens tag themselves with this modifier; the recorder emits
// `nav.screenAppear` / `nav.screenDisappear` when the wrapped view's
// onAppear/onDisappear fire.
//
// Calls `SessionRecorder.shared.record(...)` directly (singleton) instead
// of going through `@EnvironmentObject` so SwiftUI previews that don't
// inject the env object don't crash. The toggle dot and viewer still
// bind to the env-injected instance for `@Published` reactivity.

import SwiftUI

extension View {
    /// Mark this view as a top-level recorder screen. On appear / disappear
    /// the recorder logs `nav.screenAppear` / `nav.screenDisappear` with
    /// `screen = name`.
    func recorderScreen(_ name: String) -> some View {
        modifier(RecorderScreenModifier(screenName: name))
    }
}

private struct RecorderScreenModifier: ViewModifier {
    let screenName: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                SessionRecorder.shared.record(
                    category: .nav,
                    name: "nav.screenAppear",
                    screen: screenName
                )
            }
            .onDisappear {
                SessionRecorder.shared.record(
                    category: .nav,
                    name: "nav.screenDisappear",
                    screen: screenName
                )
            }
    }
}
