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
        // Time comes from the finger (web getLocalY), not ghost-top.
        let target = DropMath.target(
            ghostTop: CGPoint(x: 80, y: 80 + 100),
            finger: CGPoint(x: 80, y: 80 + 400),
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
            ghostTop: CGPoint(x: 80, y: 80 + 80),
            finger: CGPoint(x: 80, y: 80 + 200),
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

    func testTimedDropUsesFingerOnScrolledCanvasNotGhostTop() {
        // Viewport shows hours 9–16. Canvas hour 0 is above the pane.
        let hourH: CGFloat = 50
        let pane = CGRect(x: 0, y: 100, width: 400, height: 400)
        let canvas = CGRect(x: 40, y: pane.minY - 9 * hourH, width: 200, height: 24 * hourH)
        let finger = CGPoint(x: 80, y: pane.minY + 2 * hourH) // hour 11
        let ghostTop = CGPoint(x: 80, y: finger.y - 40)
        let target = DropMath.target(
            ghostTop: ghostTop,
            finger: finger,
            ghostSize: CGSize(width: 160, height: 44),
            zones: [HomeChrome.DropZone(kind: .timed("2026-09-18"), frame: canvas)],
            draggingID: "row",
            fromCalendar: false,
            calendarPane: pane,
            listPane: CGRect(x: 0, y: 520, width: 400, height: 400),
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .timed(dayISO: "2026-09-18", minutes: 11 * 60))
        // Clipping the canvas to the pane then using ghost-top would land ~04:00.
        let clippedOrigin = pane.minY
        let wrongGhost = DropMath.timedMinutes(
            fingerY: ghostTop.y,
            canvasGlobalMinY: clippedOrigin,
            pixelsPerHour: 50,
            snap: 5
        )
        XCTAssertLessThan(wrongGhost, 6 * 60)
        XCTAssertNotEqual(wrongGhost, 11 * 60)
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
            HomeChrome.DropZone(kind: .listSlot(parentID: "", index: 2), frame: CGRect(x: 12, y: 580, width: 360, height: 22))
        ]
        let target = DropMath.target(
            ghostTop: CGPoint(x: 40, y: 586),
            finger: CGPoint(x: 40, y: 590),
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
        let onMaxEdge = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 150, y: 500),
            viewport: viewport,
            band: 44,
            step: 16,
            axes: [.vertical]
        )
        XCTAssertEqual(onMaxEdge.height, 16)
        let belowPane = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 150, y: 540),
            viewport: viewport,
            band: 44,
            step: 16,
            axes: [.vertical]
        )
        XCTAssertEqual(belowPane.height, 16)
        let abovePane = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 150, y: 80),
            viewport: viewport,
            band: 44,
            step: 16,
            axes: [.vertical]
        )
        XCTAssertEqual(abovePane.height, -16)
        let ghostAtBottom = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 150, y: 430),
            viewport: viewport,
            band: 44,
            step: 16,
            axes: [.vertical],
            ghostTop: CGPoint(x: 40, y: 470),
            ghostSize: CGSize(width: 200, height: 40)
        )
        XCTAssertEqual(ghostAtBottom.height, 16)
        let midList = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 150, y: 300),
            viewport: viewport,
            band: 44,
            step: 16,
            axes: [.vertical],
            ghostTop: CGPoint(x: 40, y: 280),
            ghostSize: CGSize(width: 200, height: 40)
        )
        XCTAssertEqual(midList, .zero)
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

    func testHoldDelayMatchesWebLift() {
        XCTAssertEqual(HomeChrome.holdDelay, 0.15, accuracy: 0.0001)
        XCTAssertEqual(HomeChrome.touchSlop, 5, accuracy: 0.0001)
    }

    func testHoldPolicyAcceptsFingerOnRowAndRejectsMisses() {
        let row = CGRect(x: 12, y: 500, width: 360, height: 44)
        XCTAssertTrue(
            HoldThenDragPolicy.shouldReceive(
                enabled: true,
                finger: CGPoint(x: 40, y: 520),
                rowFrame: row
            )
        )
        XCTAssertFalse(
            HoldThenDragPolicy.shouldReceive(
                enabled: true,
                finger: CGPoint(x: 40, y: 20),
                rowFrame: row
            )
        )
        XCTAssertFalse(
            HoldThenDragPolicy.shouldReceive(
                enabled: false,
                finger: CGPoint(x: 40, y: 520),
                rowFrame: row
            )
        )
        XCTAssertFalse(
            HoldThenDragPolicy.shouldReceive(
                enabled: true,
                finger: CGPoint(x: 40, y: 520),
                rowFrame: .zero
            )
        )
    }

    func testHoldDoesNotShareWithPanEvenBeforeLift() {
        XCTAssertFalse(
            HoldThenDragPolicy.shouldRecognizeSimultaneously(otherIsPan: true, isDragging: false)
        )
        XCTAssertFalse(
            HoldThenDragPolicy.shouldRecognizeSimultaneously(otherIsPan: true, isDragging: true)
        )
        XCTAssertTrue(
            HoldThenDragPolicy.shouldRecognizeSimultaneously(otherIsPan: false, isDragging: false)
        )
        XCTAssertFalse(
            HoldThenDragPolicy.shouldRecognizeSimultaneously(otherIsPan: false, isDragging: true)
        )
    }

    func testPreferredRowFrameIgnoresEmptyRepresentable() {
        let swiftUI = CGRect(x: 12, y: 500, width: 360, height: 44)
        XCTAssertEqual(
            HoldThenDragPolicy.preferredRowFrame(uiKit: .zero, swiftUI: swiftUI),
            swiftUI
        )
        XCTAssertEqual(
            HoldThenDragPolicy.preferredRowFrame(
                uiKit: CGRect(x: 12, y: 500, width: 360, height: 44),
                swiftUI: swiftUI
            ),
            CGRect(x: 12, y: 500, width: 360, height: 44)
        )
    }

    func testBeginDragLiftsGhostAndCapturesPointer() {
        let chrome = HomeChrome()
        let frame = CGRect(x: 10, y: 400, width: 200, height: 44)
        chrome.beginDrag(
            taskID: "row",
            name: "Drag me to the calendar",
            duration: 30,
            finger: CGPoint(x: 40, y: 420),
            frame: frame
        )
        XCTAssertEqual(chrome.drag?.taskID, "row")
        XCTAssertEqual(chrome.drag?.name, "Drag me to the calendar")
        XCTAssertTrue(chrome.pointerCaptured)
        XCTAssertTrue(chrome.isLifting)
        XCTAssertEqual(chrome.ghostTop.x, 10, accuracy: 0.01)
        XCTAssertEqual(chrome.ghostTop.y, 400, accuracy: 0.01)
        chrome.cancelDrag()
    }

    func testLiftedRowAtListEdgeRequestsAutoscroll() {
        let chrome = HomeChrome()
        chrome.calendarPane = CGRect(x: 0, y: 0, width: 400, height: 364)
        chrome.listPane = CGRect(x: 0, y: 400, width: 400, height: 400)
        chrome.beginDrag(
            taskID: "photo",
            name: "Attach a photo",
            duration: 15,
            finger: CGPoint(x: 40, y: 780),
            frame: CGRect(x: 12, y: 740, width: 360, height: 44)
        )
        XCTAssertEqual(chrome.listScrollDelta.height, HomeChrome.edgeStep)
        XCTAssertGreaterThan(chrome.edgeScrollGeneration, 0)
        chrome.cancelDrag()
    }

    func testVisiblePaneBandCoversConnectRowAboveVisa() {
        let pane = CGRect(x: 0, y: 500, width: 400, height: 400)
        let band = DropMath.edgeBand(for: pane)
        XCTAssertEqual(band, 100, accuracy: 0.01)
        XCTAssertGreaterThan(band, HomeChrome.edgeBand)

        // Visa header occupies the last ~50pt; Connect sits above it. A 44pt
        // band misses that hold (`86933ab` / `pr4-86933ab-edge-scroll.png`).
        let connectFinger = CGPoint(x: 40, y: pane.maxY - 80)
        let ghostTop = CGPoint(x: 12, y: connectFinger.y - 22)
        let ghostSize = CGSize(width: 200, height: 44)
        let thin = DropMath.edgeScrollDelta(
            finger: connectFinger,
            viewport: pane,
            band: HomeChrome.edgeBand,
            step: 16,
            axes: [.vertical],
            ghostTop: ghostTop,
            ghostSize: ghostSize
        )
        XCTAssertEqual(thin, .zero)

        let thick = DropMath.edgeScrollDelta(
            finger: connectFinger,
            viewport: pane,
            band: band,
            step: 16,
            axes: [.vertical],
            ghostTop: ghostTop,
            ghostSize: ghostSize
        )
        XCTAssertEqual(thick.height, 16)

        let mid = DropMath.edgeScrollDelta(
            finger: CGPoint(x: 40, y: pane.midY),
            viewport: pane,
            band: band,
            step: 16,
            axes: [.vertical],
            ghostTop: CGPoint(x: 12, y: pane.midY - 20),
            ghostSize: ghostSize
        )
        XCTAssertEqual(mid, .zero)
    }

    func testHoldOnLastVisibleListRowAutoscrolls() {
        let chrome = HomeChrome()
        chrome.calendarPane = CGRect(x: 0, y: 0, width: 400, height: 364)
        chrome.listPane = CGRect(x: 0, y: 500, width: 400, height: 400)
        // Finger stays inside the visible list pane — not past maxY.
        chrome.beginDrag(
            taskID: "photo",
            name: "Attach a photo",
            duration: 15,
            finger: CGPoint(x: 40, y: 820),
            frame: CGRect(x: 12, y: 798, width: 360, height: 44)
        )
        XCTAssertEqual(chrome.listScrollDelta.height, HomeChrome.edgeStep)
        chrome.cancelDrag()
    }

    func testClampedOffsetMovesWhenContentIsTallerThanPane() {
        let next = HomeChrome.clampedContentOffset(
            current: .zero,
            adding: CGSize(width: 0, height: 16),
            contentSize: CGSize(width: 400, height: 1200),
            viewportSize: CGSize(width: 400, height: 400)
        )
        XCTAssertEqual(next.y, 16)
        let stuck = HomeChrome.clampedContentOffset(
            current: .zero,
            adding: CGSize(width: 0, height: 16),
            contentSize: CGSize(width: 400, height: 400),
            viewportSize: CGSize(width: 400, height: 400)
        )
        XCTAssertEqual(stuck.y, 0)
    }

    func testListEdgeHoldDoesNotReorder() {
        let listPane = CGRect(x: 0, y: 400, width: 400, height: 400)
        let target = DropMath.target(
            ghostTop: CGPoint(x: 40, y: 760),
            finger: CGPoint(x: 40, y: 780),
            ghostSize: CGSize(width: 200, height: 36),
            zones: [
                HomeChrome.DropZone(kind: .listSlot(parentID: "todo", index: 4), frame: CGRect(x: 12, y: 750, width: 360, height: 40)),
                HomeChrome.DropZone(kind: .list, frame: listPane)
            ],
            draggingID: "photo",
            fromCalendar: false,
            calendarPane: CGRect(x: 0, y: 0, width: 400, height: 364),
            listPane: listPane,
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .none)
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
        // Hour-scroller pan translation.y → setDuration (`1fc1511` scrolled
        // hours without committing; card UIControl was not under the finger).
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

    func testTitleTapIsBlockBodyNotCapsule() {
        // SpatialTap still wins the painted title (`1fc1511`). Title is on the
        // block and off the 16pt capsule so Details can open instead of composer.
        let placed = CalendarLayout.placeTimed(
            [TaskSnapshot(
                id: "timed",
                parentID: "",
                rootID: "timed",
                startDateISO: "2026-09-17",
                orderValue: 1,
                name: "PR3 timed",
                onList: false,
                isDone: false,
                isCollapsed: false,
                treeISOs: ["2026-09-17"],
                startTime: "06:00",
                duration: 30,
                notes: ""
            )],
            pixelsPerHour: 50
        )[0]
        let column: CGFloat = 220
        let title = CGPoint(x: 40, y: placed.y + 8)
        let capsule = CalendarLayout.durationCapsuleRect(
            columnIndex: 0,
            columnWidth: column,
            event: placed
        )
        XCTAssertTrue(CalendarLayout.blockContains(location: title, event: placed, columnWidth: column))
        XCTAssertFalse(CalendarLayout.touchHitsCapsule(title, capsule: capsule))
        XCTAssertTrue(
            CalendarLayout.touchHitsCapsule(CGPoint(x: capsule.midX, y: capsule.midY), capsule: capsule)
        )
        let afterPan = CGPoint(x: capsule.midX, y: capsule.midY + 74)
        XCTAssertFalse(
            CalendarLayout.touchHitsCapsule(afterPan, capsule: capsule),
            "after 74pt the finger has left the 16pt band; commit must use the shouldReceive hit"
        )
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
