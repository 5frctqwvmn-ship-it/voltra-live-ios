// RecorderBufferTests.swift
// B74-F11 — exercise the FIFO ring buffer's wrap behavior + concurrency.

import XCTest
@testable import VoltraLive

final class RecorderBufferTests: XCTestCase {

    // MARK: Wrap

    func testAppendUnderCapacityKeepsOrder() async {
        let buf = RecorderBuffer(capacity: 5)
        for i in 0..<3 {
            await buf.append(makeEvent(name: "e\(i)"))
        }
        let snap = await buf.snapshot()
        XCTAssertEqual(snap.count, 3)
        XCTAssertEqual(snap.map(\.name), ["e0", "e1", "e2"])
    }

    func testWrapDropsOldestFirst() async {
        let buf = RecorderBuffer(capacity: 5)
        for i in 0..<8 {
            await buf.append(makeEvent(name: "e\(i)"))
        }
        let snap = await buf.snapshot()
        XCTAssertEqual(snap.count, 5)
        XCTAssertEqual(snap.map(\.name), ["e3", "e4", "e5", "e6", "e7"])
    }

    func testWrapAtTenThousand() async {
        let buf = RecorderBuffer(capacity: 10_000)
        for i in 0..<10_500 {
            await buf.append(makeEvent(name: "e\(i)"))
        }
        let count = await buf.count
        let snap = await buf.snapshot()
        XCTAssertEqual(count, 10_000)
        XCTAssertEqual(snap.count, 10_000)
        XCTAssertEqual(snap.first?.name, "e500")
        XCTAssertEqual(snap.last?.name, "e10499")
    }

    // MARK: Thread-safety under concurrent writers

    func testConcurrentWritersDoNotLoseEvents() async {
        let buf = RecorderBuffer(capacity: 1_000)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<500 {
                group.addTask {
                    await buf.append(self.makeEvent(name: "c\(i)"))
                }
            }
        }
        let count = await buf.count
        XCTAssertEqual(count, 500)
    }

    func testConcurrentWritersOverflowConvergesToCapacity() async {
        let buf = RecorderBuffer(capacity: 100)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<500 {
                group.addTask {
                    await buf.append(self.makeEvent(name: "x\(i)"))
                }
            }
        }
        let count = await buf.count
        XCTAssertEqual(count, 100)
    }

    // MARK: Clear

    func testClearEmptiesBuffer() async {
        let buf = RecorderBuffer(capacity: 10)
        for i in 0..<5 { await buf.append(makeEvent(name: "e\(i)")) }
        await buf.clear()
        let snap = await buf.snapshot()
        let count = await buf.count
        XCTAssertEqual(snap.count, 0)
        XCTAssertEqual(count, 0)
    }

    func testReuseAfterClear() async {
        let buf = RecorderBuffer(capacity: 3)
        for i in 0..<3 { await buf.append(makeEvent(name: "old\(i)")) }
        await buf.clear()
        for i in 0..<2 { await buf.append(makeEvent(name: "new\(i)")) }
        let snap = await buf.snapshot()
        XCTAssertEqual(snap.map(\.name), ["new0", "new1"])
    }

    // MARK: Helpers

    private func makeEvent(name: String) -> RecorderEvent {
        RecorderEvent(
            id: UUID(),
            sessionId: UUID(),
            actionId: nil,
            timestamp: Date(),
            monotonic: 0,
            category: .ui,
            name: name,
            screen: nil,
            metadata: [:],
            error: nil,
            ble: nil
        )
    }
}
