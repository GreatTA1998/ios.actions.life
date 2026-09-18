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

    func testMorningBlockDoesNotClaimEmptyHourTwo() {
        let placed = CalendarLayout.placeTimed(
            [event(time: "00:00", duration: 106)],
            pixelsPerHour: 50
        )
        let column: CGFloat = 220
        XCTAssertFalse(
            CalendarLayout.blockContains(
                location: CGPoint(x: 40, y: 2 * 50),
                event: placed[0],
                columnWidth: column
            )
        )
        let handleY = CalendarLayout.durationHandleTop(
            duration: 106,
            y: placed[0].y,
            pixelsPerHour: 50,
            handle: 28
        )
        XCTAssertTrue(
            CalendarLayout.blockContains(
                location: CGPoint(x: 40, y: handleY + 14),
                event: placed[0],
                columnWidth: column
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
