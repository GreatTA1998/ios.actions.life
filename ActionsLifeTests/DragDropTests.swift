import CoreGraphics
import XCTest
@testable import ActionsLife

final class DragDropTests: XCTestCase {
    func testCanvasYIgnoresScrollByUsingGlobalFrame() {
        let canvasMinY: CGFloat = -400
        let tenAMGlobalY: CGFloat = -400 + 500
        let localY = DropMath.canvasY(globalY: tenAMGlobalY, canvasGlobalMinY: canvasMinY)
        XCTAssertEqual(localY, 500)
        XCTAssertEqual(CalendarLayout.minutes(atY: localY, pixelsPerHour: 50, snap: 15), 10 * 60)
    }

    func testTimedZoneBeatsHeaderAndList() {
        let zones = [
            HomeChrome.DropZone(kind: .list, frame: CGRect(x: 0, y: 600, width: 400, height: 400)),
            HomeChrome.DropZone(kind: .allDay("2026-09-18"), frame: CGRect(x: 40, y: 0, width: 200, height: 80)),
            HomeChrome.DropZone(kind: .timed("2026-09-18"), frame: CGRect(x: 40, y: 80, width: 200, height: 1200))
        ]
        // Finger must sit inside the calendar pane; probe uses ghost top (web getLocalY).
        // Keep ghostTop strictly inside the clipped timed frame (CGRect intersects is edge-exclusive).
        let target = DropMath.target(
            ghostTop: CGPoint(x: 80, y: 80 + 400),
            finger: CGPoint(x: 80, y: 500),
            ghostSize: CGSize(width: 160, height: 40),
            zones: zones,
            draggingID: "task",
            fromCalendar: false,
            calendarPane: CGRect(x: 0, y: 0, width: 400, height: 580),
            listPane: CGRect(x: 0, y: 600, width: 400, height: 400),
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .timed(dayISO: "2026-09-18", minutes: 8 * 60))
    }

    func testListToCalendarIgnoresListNestUnderFingerInCalendar() {
        let zones = [
            HomeChrome.DropZone(kind: .nest("other"), frame: CGRect(x: 12, y: 620, width: 360, height: 44)),
            HomeChrome.DropZone(kind: .listSlot(parentID: "", index: 0), frame: CGRect(x: 12, y: 600, width: 360, height: 24)),
            HomeChrome.DropZone(kind: .timed("2026-09-18"), frame: CGRect(x: 40, y: 80, width: 200, height: 1200))
        ]
        let target = DropMath.target(
            ghostTop: CGPoint(x: 80, y: 80 + 200),
            finger: CGPoint(x: 80, y: 220),
            ghostSize: CGSize(width: 160, height: 40),
            zones: zones,
            draggingID: "dragged",
            fromCalendar: false,
            calendarPane: CGRect(x: 0, y: 0, width: 400, height: 580),
            listPane: CGRect(x: 0, y: 600, width: 400, height: 400),
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .timed(dayISO: "2026-09-18", minutes: 4 * 60))
    }

    func testHeaderDropIsAllDay() {
        let zones = [
            HomeChrome.DropZone(kind: .allDay("2026-09-18"), frame: CGRect(x: 40, y: 0, width: 200, height: 80)),
            HomeChrome.DropZone(kind: .timed("2026-09-18"), frame: CGRect(x: 40, y: 80, width: 200, height: 1200))
        ]
        let target = DropMath.target(
            ghostTop: CGPoint(x: 80, y: 20),
            finger: CGPoint(x: 80, y: 30),
            ghostSize: CGSize(width: 160, height: 36),
            zones: zones,
            draggingID: "task",
            fromCalendar: false,
            calendarPane: CGRect(x: 0, y: 0, width: 400, height: 800),
            listPane: CGRect(x: 0, y: 820, width: 400, height: 200),
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .allDay("2026-09-18"))
    }

    func testListSlotBeatsBroadListZone() {
        let zones = [
            HomeChrome.DropZone(kind: .list, frame: CGRect(x: 0, y: 400, width: 400, height: 400)),
            HomeChrome.DropZone(kind: .listSlot(parentID: "", index: 2), frame: CGRect(x: 12, y: 480, width: 360, height: 22))
        ]
        let target = DropMath.target(
            ghostTop: CGPoint(x: 40, y: 486),
            finger: CGPoint(x: 40, y: 490),
            ghostSize: CGSize(width: 200, height: 36),
            zones: zones,
            draggingID: "task",
            fromCalendar: false,
            calendarPane: CGRect(x: 0, y: 0, width: 400, height: 380),
            listPane: CGRect(x: 0, y: 400, width: 400, height: 400),
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .listSlot(parentID: "", index: 2))
    }

    func testCannotNestUnderSelf() {
        let zones = [
            HomeChrome.DropZone(kind: .nest("dragged"), frame: CGRect(x: 12, y: 480, width: 360, height: 44)),
            HomeChrome.DropZone(kind: .listSlot(parentID: "", index: 1), frame: CGRect(x: 12, y: 530, width: 360, height: 22))
        ]
        // Probe sits on the slot below the self-nest row (2px ghost-top probe cannot hit both).
        let target = DropMath.target(
            ghostTop: CGPoint(x: 40, y: 536),
            finger: CGPoint(x: 40, y: 540),
            ghostSize: CGSize(width: 200, height: 36),
            zones: zones,
            draggingID: "dragged",
            fromCalendar: false,
            calendarPane: CGRect(x: 0, y: 0, width: 400, height: 380),
            listPane: CGRect(x: 0, y: 400, width: 400, height: 400),
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .listSlot(parentID: "", index: 1))

        let overSelf = DropMath.target(
            ghostTop: CGPoint(x: 40, y: 490),
            finger: CGPoint(x: 40, y: 495),
            ghostSize: CGSize(width: 200, height: 36),
            zones: zones,
            draggingID: "dragged",
            fromCalendar: false,
            calendarPane: CGRect(x: 0, y: 0, width: 400, height: 380),
            listPane: CGRect(x: 0, y: 400, width: 400, height: 400),
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(overSelf, .none)
    }

    func testEdgeScrollDeltaMatchesExpoBand() {
        let viewport = CGRect(x: 0, y: 100, width: 300, height: 400)
        let up = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 150, y: 110),
            viewport: viewport,
            band: 44,
            step: 16,
            axes: [.vertical]
        )
        XCTAssertEqual(up.height, -16)
        let down = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 150, y: 480),
            viewport: viewport,
            band: 44,
            step: 16,
            axes: [.vertical]
        )
        XCTAssertEqual(down.height, 16)
        let outside = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 400, y: 110),
            viewport: viewport,
            band: 44,
            step: 16,
            axes: [.vertical]
        )
        XCTAssertEqual(outside, .zero)
    }

    func testClampSplitAllowsFullscreenList() {
        let height: CGFloat = 800
        let minF = HomeChrome.clampSplitFraction(0, height: height)
        let maxF = HomeChrome.clampSplitFraction(1, height: height)
        let remaining = height - HomeChrome.splitHandle
        // Web mobile: list ∈ [48pt, full remaining] — calendar may collapse to 0.
        XCTAssertEqual(minF, Double(HomeChrome.splitMinPane / remaining), accuracy: 0.0001)
        XCTAssertEqual(maxF, 1, accuracy: 0.0001)
        XCTAssertLessThan(minF, 0.1)
    }

    func testClipDropsOffPaneZones() {
        let clipped = DropMath.clip(
            CGRect(x: 0, y: 600, width: 400, height: 40),
            to: CGRect(x: 0, y: 0, width: 400, height: 500)
        )
        XCTAssertNil(clipped)
    }

    func testDurationResizeCapturesPointerAndSnaps() {
        let chrome = HomeChrome()
        chrome.pixelsPerHour = 50
        chrome.snapInterval = 15
        XCTAssertFalse(chrome.pointerCaptured)
        chrome.beginDurationResize(taskID: "block", duration: 30)
        // Duration pan must not flip scrollDisabled — that rebuild cancels the handle.
        XCTAssertFalse(chrome.pointerCaptured)
        XCTAssertEqual(chrome.durationResize?.taskID, "block")
        chrome.moveDurationResize(deltaY: 50)
        let result = chrome.finishDurationResize()
        XCTAssertEqual(result?.taskID, "block")
        XCTAssertEqual(result?.duration, 90)
        XCTAssertFalse(chrome.pointerCaptured)
        XCTAssertNil(chrome.durationResize)
    }

    func testDurationPanDownLengthensBlock() {
        let chrome = HomeChrome()
        chrome.pixelsPerHour = 50
        chrome.snapInterval = 15
        chrome.beginDurationResize(taskID: "block", duration: 30)
        chrome.moveDurationResize(deltaY: 74)
        let result = chrome.finishDurationResize()
        XCTAssertEqual(
            result?.duration,
            CalendarLayout.snapDuration(
                CalendarLayout.previewDuration(start: 30, deltaY: 74, pixelsPerHour: 50),
                snap: 15
            )
        )
        XCTAssertGreaterThan(result?.duration ?? 0, 30)
    }

    func testDurationPanHitsVisibleCapsuleNotCardBody() {
        // 16pt capsule at the bottom of a 36pt card. Title / card body still
        // opens Details (`b45eccd` bottom-half handle ate the title tap).
        let event = CalendarLayout.placeTimed(
            [TaskSnapshot(
                id: "timed",
                parentID: "",
                rootID: "timed",
                startDateISO: "2026-09-17",
                orderValue: 1,
                name: "Event",
                onList: false,
                isDone: false,
                isCollapsed: false,
                treeISOs: ["2026-09-17"],
                startTime: "03:00",
                duration: 30,
                notes: ""
            )],
            pixelsPerHour: 50
        )[0]
        let capsule = CalendarLayout.durationCapsuleRect(
            columnIndex: 14,
            columnWidth: 220,
            event: event
        )
        XCTAssertEqual(capsule.height, 16, accuracy: 0.01)
        XCTAssertEqual(capsule.minY, event.y + 36 - 16, accuracy: 0.01)
        XCTAssertFalse(
            CalendarLayout.touchHitsCapsule(CGPoint(x: capsule.midX, y: event.y + 8), capsule: capsule),
            "title / card body must still open Details"
        )
        XCTAssertTrue(
            CalendarLayout.touchHitsCapsule(CGPoint(x: capsule.midX, y: capsule.midY), capsule: capsule)
        )
        XCTAssertEqual(HomeChrome.durationCapsuleHit, 16)
        XCTAssertLessThan(HomeChrome.durationCapsuleHit, 36 / 2 + 1)
    }

    func testLiftIgnoresDurationHandleBand() {
        XCTAssertEqual(HomeChrome.durationHandleHit, 28)
        let card = CGRect(x: 0, y: 0, width: 200, height: 36)
        let handleY = card.height - HomeChrome.durationHandleHit
        XCTAssertLessThan(handleY, 12)
        XCTAssertGreaterThan(card.height - handleY, 20)
    }

    func testCancelDurationResizeClearsPointerCapture() {
        let chrome = HomeChrome()
        chrome.beginDurationResize(taskID: "block", duration: 30)
        chrome.cancelDurationResize()
        XCTAssertFalse(chrome.pointerCaptured)
    }
}
