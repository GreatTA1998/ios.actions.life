import XCTest
@testable import ActionsLife

final class CalendarLayoutTests: XCTestCase {
    func testTenAMSitsAtTenOnTheDayCanvas() {
        let placed = CalendarLayout.placeTimed([event(time: "10:00", duration: 60)], pixelsPerHour: 50)
        XCTAssertEqual(placed.count, 1)
        XCTAssertEqual(placed[0].y, 10 * 50)
        XCTAssertEqual(placed[0].height, 50)
    }

    func testDurationMapsToHourHeight() {
        let placed = CalendarLayout.placeTimed([event(time: "08:30", duration: 106)], pixelsPerHour: 50)
        XCTAssertEqual(placed[0].y, 8.5 * 50, accuracy: 0.01)
        XCTAssertEqual(placed[0].height, 106.0 / 60 * 50, accuracy: 0.01)
    }

    func testMissingTimeGoesAllDayNotOnHourGrid() {
        let split = CalendarLayout.split(tasks: [
            event(id: "untimed", time: "", duration: 30),
            event(id: "timed", time: "10:00", duration: 30)
        ])
        XCTAssertEqual(split.allDay.map(\.id), ["untimed"])
        XCTAssertEqual(split.timed.map(\.id), ["timed"])
    }

    func testParsesTimesWithSeconds() {
        XCTAssertEqual(DateISO.minutes(fromClock: "10:00"), 600)
        XCTAssertEqual(DateISO.minutes(fromClock: "10:00:00"), 600)
        XCTAssertEqual(DateISO.minutes(fromClock: "07:15"), 435)
    }

    func testCanvasCoversFullDay() {
        XCTAssertEqual(CalendarLayout.hours().count, 24)
        XCTAssertEqual(CalendarLayout.canvasHeight(pixelsPerHour: 50), 24 * 50)
    }

    func testDropYMapsToSnappedClock() {
        let minutes = CalendarLayout.minutes(atY: 10 * 50 + 20, pixelsPerHour: 50, snap: 15)
        XCTAssertEqual(minutes, 10 * 60 + 30)
        XCTAssertEqual(CalendarLayout.clock(fromMinutes: minutes), "10:30")
    }

    func testDropYRoundsDownWhenCloserToEarlierSnap() {
        let minutes = CalendarLayout.minutes(atY: 10 * 50 + 5, pixelsPerHour: 50, snap: 15)
        XCTAssertEqual(minutes, 10 * 60)
        XCTAssertEqual(CalendarLayout.clock(fromMinutes: minutes), "10:00")
    }

    func testHourLabelsAreBareNumbers() {
        XCTAssertEqual(CalendarLayout.hourLabel(9), "9")
        XCTAssertEqual(CalendarLayout.hourLabel(0), "0")
    }

    func testDurationHandleSitsOnBlockBottomNotPositionSlot() {
        // 30 min at 50px/hour is below 36pt card floor; handle is the bottom 28pt.
        let y = CalendarLayout.y(fromMinutes: 22 * 60, pixelsPerHour: 50)
        XCTAssertEqual(y, 22 * 50, accuracy: 0.01)
        let top = CalendarLayout.durationHandleTop(duration: 30, y: y, pixelsPerHour: 50, handle: 28)
        XCTAssertEqual(top, y + 36 - 28, accuracy: 0.01)
        XCTAssertGreaterThan(top, 21 * 50)
    }

    func testBlockContainsStopsComposerOnDurationEdge() {
        let placed = CalendarLayout.placeTimed(
            [event(time: "02:00", duration: 30)],
            pixelsPerHour: 50
        )
        XCTAssertEqual(placed.count, 1)
        let column: CGFloat = 220
        XCTAssertTrue(
            CalendarLayout.blockContains(
                location: CGPoint(x: 40, y: placed[0].y + 20),
                event: placed[0],
                columnWidth: column
            )
        )
        XCTAssertFalse(
            CalendarLayout.blockContains(
                location: CGPoint(x: 40, y: placed[0].y - 8),
                event: placed[0],
                columnWidth: column
            )
        )
    }

    func testEmptyHourTapIsNotSwallowedByAfternoonBlock() {
        // Seed-like: 12:30 for 106 min must not eat an hour-2 SpatialTap (`d94cb61`).
        let placed = CalendarLayout.placeTimed(
            [event(time: "12:30", duration: 106)],
            pixelsPerHour: 50
        )
        let column: CGFloat = 220
        let hour2 = CGPoint(x: 40, y: 2 * 50 + 10)
        XCTAssertFalse(
            CalendarLayout.blockContains(location: hour2, event: placed[0], columnWidth: column)
        )
        XCTAssertTrue(
            CalendarLayout.blockContains(
                location: CGPoint(x: 40, y: placed[0].y + 10),
                event: placed[0],
                columnWidth: column
            )
        )
        // Y-only would have treated the trailing gutter as “on the block”.
        XCTAssertFalse(
            CalendarLayout.blockContains(
                location: CGPoint(x: column + 24, y: placed[0].y + 10),
                event: placed[0],
                columnWidth: column
            )
        )
    }

    func testDurationHandleWindowRectIsBottomBandNotCardBody() {
        let card = CGRect(x: 40, y: 200, width: 200, height: 36)
        let handle = CalendarLayout.durationHandleWindowRect(
            handleInWindow: .zero,
            hostInWindow: card,
            handleHeight: 16
        )
        XCTAssertEqual(handle.height, 16, accuracy: 0.01)
        XCTAssertEqual(handle.maxY, card.maxY, accuracy: 0.01)
        XCTAssertFalse(
            CalendarLayout.touchHitsCapsule(CGPoint(x: card.midX, y: card.minY + 8), capsule: handle),
            "card body must still open Details"
        )
        XCTAssertTrue(
            CalendarLayout.touchHitsCapsule(CGPoint(x: card.midX, y: handle.midY), capsule: handle)
        )
        let painted = CGRect(x: 40, y: 220, width: 200, height: 16)
        XCTAssertEqual(
            CalendarLayout.durationHandleWindowRect(handleInWindow: painted, hostInWindow: card).height,
            16,
            accuracy: 0.01
        )
    }

    func testHourContentPointDoesNotDoubleCountOffset() {
        // Classic UIScrollView: bounds.origin == contentOffset.
        let classic = CalendarLayout.hourContentPoint(
            locationInScroll: CGPoint(x: 40, y: 270),
            contentOffset: CGPoint(x: 0, y: 200),
            boundsOrigin: CGPoint(x: 0, y: 200)
        )
        XCTAssertEqual(classic.x, 40, accuracy: 0.01)
        XCTAssertEqual(classic.y, 270, accuracy: 0.01)
        // SwiftUI UIScrollView: bounds.origin stays zero.
        let swiftUI = CalendarLayout.hourContentPoint(
            locationInScroll: CGPoint(x: 40, y: 70),
            contentOffset: CGPoint(x: 0, y: 200),
            boundsOrigin: .zero
        )
        XCTAssertEqual(swiftUI.x, 40, accuracy: 0.01)
        XCTAssertEqual(swiftUI.y, 270, accuracy: 0.01)
    }

    func testBlockFrameOriginMatchesPaintedCard() {
        // TimedCardLayout places at this origin — not offset/position/padding.
        let placed = CalendarLayout.placeTimed(
            [event(time: "05:00", duration: 30)],
            pixelsPerHour: 50
        )[0]
        let frame = CalendarLayout.blockFrame(event: placed, columnWidth: 220)
        XCTAssertEqual(frame.minX, 6, accuracy: 0.01)
        XCTAssertEqual(frame.minY, 5 * 50, accuracy: 0.01)
        XCTAssertEqual(frame.height, 36, accuracy: 0.01)
        XCTAssertEqual(frame.width, 208, accuracy: 0.01)
        let capsule = CalendarLayout.durationCapsuleRect(
            columnIndex: 0,
            columnWidth: 220,
            event: placed
        )
        XCTAssertEqual(capsule.minY, frame.maxY - 16, accuracy: 0.01)
        XCTAssertEqual(capsule.maxY, frame.maxY, accuracy: 0.01)
        XCTAssertEqual(capsule.height, HomeChrome.durationCapsuleHit, accuracy: 0.01)
        XCTAssertFalse(
            CalendarLayout.touchHitsCapsule(
                CGPoint(x: frame.midX, y: frame.minY + 8),
                capsule: capsule
            ),
            "title / card body must still open Details"
        )
    }

    func testDurationCapsuleRectIsBottomBandInContentSpace() {
        let placed = CalendarLayout.placeTimed(
            [event(time: "03:00", duration: 30)],
            pixelsPerHour: 50
        )[0]
        let capsule = CalendarLayout.durationCapsuleRect(
            columnIndex: 14,
            columnWidth: 220,
            event: placed
        )
        XCTAssertEqual(capsule.minX, 14 * 220 + 6, accuracy: 0.01)
        XCTAssertEqual(capsule.minY, placed.y + 36 - 16, accuracy: 0.01)
        XCTAssertEqual(capsule.height, 16, accuracy: 0.01)
        XCTAssertEqual(capsule.width, 220 - 12, accuracy: 0.01)
        XCTAssertFalse(
            CalendarLayout.touchHitsCapsule(
                CGPoint(x: capsule.midX, y: placed.y + 8),
                capsule: capsule
            )
        )
        XCTAssertTrue(
            CalendarLayout.touchHitsCapsule(
                CGPoint(x: capsule.midX, y: capsule.midY),
                capsule: capsule
            )
        )
    }

    func testDurationCapsuleSitsOnCardNotNextHour() {
        // 106 min from midnight is shorter than two hours; the capsule is the
        // card bottom, not a stray overlay on empty hour 2 (`23f0dce`).
        let placed = CalendarLayout.placeTimed(
            [event(time: "00:00", duration: 106)],
            pixelsPerHour: 50
        )
        let cardBottom = placed[0].y + max(placed[0].height, 36)
        let handleTop = CalendarLayout.durationHandleTop(
            duration: 106,
            y: placed[0].y,
            pixelsPerHour: 50,
            handle: 28
        )
        XCTAssertEqual(handleTop + 28, cardBottom, accuracy: 0.01)
        XCTAssertLessThan(cardBottom, 2 * 50)
        XCTAssertFalse(
            CalendarLayout.blockContains(
                location: CGPoint(x: 40, y: 2 * 50),
                event: placed[0],
                columnWidth: 220
            )
        )
        XCTAssertTrue(
            CalendarLayout.blockContains(
                location: CGPoint(x: 40, y: handleTop + 14),
                event: placed[0],
                columnWidth: 220
            )
        )
    }

    func testPreviewDurationMatchesWebPixelsPerHour() {
        // 50 px/hour → 1.2 minutes per point; +50pt adds 60 minutes.
        let preview = CalendarLayout.previewDuration(start: 30, deltaY: 50, pixelsPerHour: 50)
        XCTAssertEqual(preview, 90, accuracy: 0.01)
        let floor = CalendarLayout.previewDuration(start: 5, deltaY: -400, pixelsPerHour: 50)
        XCTAssertEqual(floor, Double(CalendarLayout.minimumEventHeight) / 50 * 60, accuracy: 0.01)
    }

    func testSnapDurationRoundsToInterval() {
        XCTAssertEqual(CalendarLayout.snapDuration(37, snap: 15), 30)
        XCTAssertEqual(CalendarLayout.snapDuration(38, snap: 15), 45)
        XCTAssertEqual(CalendarLayout.snapDuration(2, snap: 15), 15)
    }

    func testNowScrollYLeavesHeadroom() {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents(year: 2026, month: 9, day: 18, hour: 10, minute: 0)
        comps.timeZone = calendar.timeZone
        let now = calendar.date(from: comps) ?? Date()
        XCTAssertEqual(
            CalendarLayout.nowScrollY(now: now, calendar: calendar, pixelsPerHour: 50, headroom: 48),
            10 * 50 - 48,
            accuracy: 0.01
        )
    }

    func testTimedContentOffsetJumpsToEveningNowNotMorning() {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents(year: 2026, month: 9, day: 18, hour: 22, minute: 0)
        comps.timeZone = calendar.timeZone
        let now = calendar.date(from: comps) ?? Date()
        let offset = CalendarLayout.timedContentOffset(
            todayIndex: 14,
            columnWidth: 220,
            now: now,
            calendar: calendar,
            pixelsPerHour: 50,
            headroom: 48
        )
        XCTAssertEqual(offset.x, 14 * 220, accuracy: 0.01)
        XCTAssertEqual(offset.y, 22 * 50 - 48, accuracy: 0.01)
        XCTAssertGreaterThan(offset.y, 15 * 50)
        let origin = CalendarLayout.timedContentOffset(
            todayIndex: 0,
            columnWidth: 220,
            now: now,
            calendar: calendar,
            pixelsPerHour: 50,
            headroom: 48
        )
        XCTAssertEqual(origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(origin.y, offset.y, accuracy: 0.01)
    }

    func testDayWindowIsPastPlusTodayPlusFuture() {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents(year: 2026, month: 9, day: 18)
        comps.timeZone = calendar.timeZone
        let now = calendar.date(from: comps) ?? Date()
        let days = CalendarLayout.dayWindow(around: now, past: 2, future: 3, calendar: calendar)
        XCTAssertEqual(days.count, 6)
        XCTAssertEqual(DateISO.dayString(from: days.first ?? now, calendar: calendar), "2026-09-16")
        XCTAssertEqual(DateISO.dayString(from: days.last ?? now, calendar: calendar), "2026-09-21")
    }

    private func event(id: String = "timed", time: String, duration: Double) -> TaskSnapshot {
        TaskSnapshot(
            id: id,
            parentID: "",
            rootID: id,
            startDateISO: "2026-09-17",
            orderValue: 1,
            name: "Event",
            onList: false,
            isDone: false,
            isCollapsed: false,
            treeISOs: ["2026-09-17"],
            startTime: time,
            duration: duration,
            notes: ""
        )
    }
}
