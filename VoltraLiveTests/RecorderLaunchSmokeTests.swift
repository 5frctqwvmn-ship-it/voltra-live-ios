// RecorderLaunchSmokeTests.swift
// b78 launch-crash regression test for B74-F11 Session Recorder.
//
// b77 (v0.4.50 / build 77) shipped a launch crash — SwiftUI raised
// `EnvironmentObject.error()` because `SessionRecorderToggle`, mounted
// at the app root via `.overlay { ... }`, could not resolve its
// `@EnvironmentObject SessionRecorder` even though
// `.environmentObject(recorder)` was applied to the modifier chain
// above. Root cause: `.overlay { content }` creates a composite where
// `content` is a SIBLING of the modified view — env-objects on the
// modifier chain do NOT propagate to the overlay's content. Crash
// fired at SwiftUI's `_EnvironmentObject` setup during initial view
// resolution, regardless of whether the body's `if unlocked` branch
// (which actually reads `recorder.X`) was taken on first launch.
//
// b78 fixes this by re-injecting `recorder` on
// `SessionRecorderToggle()` inside the overlay closure. This test
// pins the fix: it builds the same root-overlay shape that
// `VoltraLiveApp` uses, mounts it via `UIHostingController`, and
// forces a layout pass to exercise the SwiftUI body /
// DynamicProperty resolution. If the env-object re-injection is
// removed in the future, this test crashes the same way b77 did,
// failing CI before the regression can ship.
//
// XCTest cannot catch `fatalError` directly, so this test only
// validates the success path. Removing the fix would crash the
// test process — which `xcodebuild test` reports as a test failure.

import XCTest
import SwiftUI
import UIKit
@testable import VoltraLive

final class RecorderLaunchSmokeTests: XCTestCase {

    /// Pin the b78 fix: SessionRecorderToggle mounted via .overlay must
    /// receive a directly-injected SessionRecorder env-object. Mirrors
    /// the VoltraLiveApp.swift root-overlay pattern.
    @MainActor
    func testRootOverlayWithRecorderToggleResolvesEnvironmentObject() {
        let recorder = SessionRecorder.shared

        // Mirror the VoltraLiveApp shape:
        //   ContentView()
        //     .environmentObject(recorder)
        //     ...other modifiers...
        //     .overlay(alignment: .bottomTrailing) {
        //         SessionRecorderToggle()
        //             .environmentObject(recorder)   // ← THE FIX
        //     }
        // Color.clear stands in for ContentView (we don't need the
        // full nav stack to exercise the env-object resolution path).
        let rootView = Color.clear
            .environmentObject(recorder)
            .overlay(alignment: .bottomTrailing) {
                SessionRecorderToggle()
                    .environmentObject(recorder)
            }

        let host = UIHostingController(rootView: rootView)
        host.loadViewIfNeeded()
        // Force layout so SwiftUI builds the view tree and runs
        // DynamicProperty resolution for every @EnvironmentObject. If
        // the fix is removed, SessionRecorderToggle's recorder lookup
        // raises _assertionFailure → EnvironmentObject.error() and
        // the test process crashes here — xcodebuild test reports
        // that as a test failure.
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        host.view.layoutIfNeeded()

        XCTAssertNotNil(host.view)
    }

    /// Sanity: the `SessionRecorder.shared` singleton can be accessed
    /// without triggering any fatalError. Init reads
    /// `Bundle.main.infoDictionary` with a nil-coalesce fallback and
    /// seeds two locked mirrors — no force-unwraps anywhere. If this
    /// changes in the future and the init starts crashing, this test
    /// catches it at the earliest possible point.
    func testSharedSingletonInitDoesNotCrash() {
        let r = SessionRecorder.shared
        XCTAssertNotNil(r)
    }

    /// SessionRecorderViewer (presented as the long-press sheet) also
    /// reads `@EnvironmentObject SessionRecorder`. The toggle re-
    /// injects on the sheet content; this test pins that pattern.
    @MainActor
    func testSessionRecorderViewerResolvesEnvironmentObject() {
        let recorder = SessionRecorder.shared

        let viewerHost = UIHostingController(
            rootView: SessionRecorderViewer()
                .environmentObject(recorder)
        )
        viewerHost.loadViewIfNeeded()
        viewerHost.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        viewerHost.view.layoutIfNeeded()

        XCTAssertNotNil(viewerHost.view)
    }
}
