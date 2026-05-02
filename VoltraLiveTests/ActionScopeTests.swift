// ActionScopeTests.swift
// B74-F11 — task-local actionId propagation.

import XCTest
@testable import VoltraLive

final class ActionScopeTests: XCTestCase {

    func testNilOutsideAnyScope() {
        XCTAssertNil(ActionScope.currentActionId)
    }

    func testSetInsideScope() {
        let id = UUID()
        ActionScope.$currentActionId.withValue(id) {
            XCTAssertEqual(ActionScope.currentActionId, id)
        }
        XCTAssertNil(ActionScope.currentActionId, "scope must clear on exit")
    }

    func testNestedScopesShadow() {
        let outer = UUID()
        let inner = UUID()
        ActionScope.$currentActionId.withValue(outer) {
            XCTAssertEqual(ActionScope.currentActionId, outer)
            ActionScope.$currentActionId.withValue(inner) {
                XCTAssertEqual(ActionScope.currentActionId, inner)
            }
            XCTAssertEqual(ActionScope.currentActionId, outer,
                           "outer scope must restore after inner returns")
        }
    }

    func testPropagatesIntoUnstructuredTask() async {
        let id = UUID()
        let captured: UUID? = await ActionScope.$currentActionId.withValue(id) {
            await withCheckedContinuation { (cont: CheckedContinuation<UUID?, Never>) in
                Task {
                    cont.resume(returning: ActionScope.currentActionId)
                }
            }
        }
        XCTAssertEqual(captured, id,
                       "Task { } inherits task-local from its launching context")
    }

    func testPropagatesAcrossAsyncCallChain() async {
        let id = UUID()
        let captured: UUID? = await ActionScope.$currentActionId.withValue(id) {
            await deeplyNested()
        }
        XCTAssertEqual(captured, id)
    }

    func testNilAmbientAfterTaskExit() async {
        let id = UUID()
        await ActionScope.$currentActionId.withValue(id) {
            _ = await deeplyNested()
        }
        XCTAssertNil(ActionScope.currentActionId)
    }

    private func deeplyNested() async -> UUID? {
        // Simulate a few async hops; task-local should still be visible.
        await Task.yield()
        return ActionScope.currentActionId
    }
}
