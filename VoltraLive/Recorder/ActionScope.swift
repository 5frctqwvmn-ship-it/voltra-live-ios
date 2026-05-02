// ActionScope.swift
// B74-F11 Session Recorder — task-local actionId propagation.
//
// Spec: docs/handoff/SESSION_RECORDER_SPEC.md "ActionScope".
//
// User-initiated UI actions mint a fresh `UUID` and run downstream work
// inside `ActionScope.$currentActionId.withValue(id) { … }`. Every
// `SessionRecorder.record(...)` call inside that scope (including
// `Task { }` children, which inherit task-local values) auto-stamps the
// id on its event without manual threading.
//
// Events emitted outside any scope have `actionId = nil` ("ambient").

import Foundation

enum ActionScope {
    /// Task-local id for the action currently in flight. `nil` outside
    /// any `withValue` scope.
    @TaskLocal static var currentActionId: UUID?
}
