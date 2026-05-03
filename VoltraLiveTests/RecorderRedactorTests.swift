// RecorderRedactorTests.swift
// B74-F11 — pin the PII rules from SESSION_RECORDER_SPEC.md "Redaction".

import XCTest
@testable import VoltraLive

final class RecorderRedactorTests: XCTestCase {

    func testPeripheralNameMapsToStableUUIDPerName() {
        let r = RecorderRedactor()
        let a1 = r.redactedPeripheralId(name: "VOLTRA Left")
        let a2 = r.redactedPeripheralId(name: "VOLTRA Left")
        let b  = r.redactedPeripheralId(name: "VOLTRA Right")

        XCTAssertEqual(a1, a2, "same name must map to the same redacted id")
        XCTAssertNotEqual(a1, b, "different names must map to different ids")
        XCTAssertNotNil(UUID(uuidString: a1), "redacted id should be UUID-shaped")
        XCTAssertNotNil(UUID(uuidString: b),  "redacted id should be UUID-shaped")
    }

    func testRedactorInstancesAreIndependent() {
        let r1 = RecorderRedactor()
        let r2 = RecorderRedactor()
        let id1 = r1.redactedPeripheralId(name: "VOLTRA Left")
        let id2 = r2.redactedPeripheralId(name: "VOLTRA Left")
        // Same input, different redactor → different ids (each owns its own table).
        XCTAssertNotEqual(id1, id2)
    }

    func testFreeTextRedactsToLengthOnly() {
        let r = RecorderRedactor()
        XCTAssertEqual(r.redactedFreeText("Bench Press"), "<redacted:len=11>")
        XCTAssertEqual(r.redactedFreeText(""),            "<redacted:len=0>")
        XCTAssertEqual(r.redactedFreeText("Z"),           "<redacted:len=1>")
    }

    func testFreeTextDoesNotLeakContent() {
        let r = RecorderRedactor()
        let secret = "user-private-day-name-abcdef"
        let red = r.redactedFreeText(secret)
        XCTAssertFalse(red.contains("user"))
        XCTAssertFalse(red.contains("private"))
        XCTAssertFalse(red.contains("abcdef"))
    }

    func testUnsafeRawPassesThroughUnchanged() {
        let r = RecorderRedactor()
        XCTAssertEqual(r.unsafeRaw("preserved"), "preserved")
        XCTAssertEqual(r.unsafeRaw(42), 42)
        XCTAssertEqual(r.unsafeRaw(true), true)
    }

    func testConcurrentPeripheralNameLookupsAreSafe() {
        let r = RecorderRedactor()
        let queue = DispatchQueue(label: "redactor-test", attributes: .concurrent)
        let group = DispatchGroup()
        var collected: [String: Set<String>] = ["L": [], "R": []]
        let collectionLock = NSLock()
        for _ in 0..<200 {
            group.enter()
            queue.async {
                let l = r.redactedPeripheralId(name: "L")
                let rt = r.redactedPeripheralId(name: "R")
                collectionLock.lock()
                collected["L"]?.insert(l)
                collected["R"]?.insert(rt)
                collectionLock.unlock()
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(collected["L"]?.count, 1, "L name must produce exactly one redacted id across concurrent callers")
        XCTAssertEqual(collected["R"]?.count, 1, "R name must produce exactly one redacted id across concurrent callers")
    }
}
