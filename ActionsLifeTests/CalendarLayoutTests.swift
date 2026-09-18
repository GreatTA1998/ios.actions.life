import UIKit
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

    func testHourContentPointAddsParentDayOffsetWhenHourScrollerIsViewportWide() {
        // Nested 1-axis: hour scroller is viewport-wide; today is column 14.
        // Finger on the painted 16pt capsule must hit that rect (`e2fba41`
        // missed capsules at todayIndex × columnWidth).
        let placed = CalendarLayout.placeTimed(
            [event(time: "06:00", duration: 30)],
            pixelsPerHour: 50
        )[0]
        let columnWidth: CGFloat = 220
        let columnIndex = 14
        let capsule = CalendarLayout.durationCapsuleRect(
            columnIndex: columnIndex,
            columnWidth: columnWidth,
            event: placed
        )
        let hourOffsetY: CGFloat = 2 * 50
        let viewportX = capsule.midX - CGFloat(columnIndex) * columnWidth
        let viewportY = capsule.midY - hourOffsetY
        let content = CalendarLayout.hourContentPoint(
            locationInScroll: CGPoint(x: viewportX, y: viewportY),
            contentOffset: CGPoint(x: 0, y: hourOffsetY),
            boundsOrigin: .zero,
            hourContentWidth: 390,
            hourBoundsWidth: 390,
            horizontalContentOffset: CGFloat(columnIndex) * columnWidth
        )
        XCTAssertEqual(content.x, capsule.midX, accuracy: 0.01)
        XCTAssertEqual(content.y, capsule.midY, accuracy: 0.01)
        let hit = CalendarLayout.hitDurationCapsule(
            contentPoint: content,
            capsules: [
                CalendarLayout.DurationCapsuleTarget(taskID: "timed", duration: 30, rect: capsule)
            ]
        )
        XCTAssertEqual(hit?.taskID, "timed")
        let title = CalendarLayout.hourContentPoint(
            locationInScroll: CGPoint(x: viewportX, y: placed.y + 8 - hourOffsetY),
            contentOffset: CGPoint(x: 0, y: hourOffsetY),
            boundsOrigin: .zero,
            hourContentWidth: 390,
            hourBoundsWidth: 390,
            horizontalContentOffset: CGFloat(columnIndex) * columnWidth
        )
        XCTAssertNil(
            CalendarLayout.hitDurationCapsule(
                contentPoint: title,
                capsules: [
                    CalendarLayout.DurationCapsuleTarget(taskID: "timed", duration: 30, rect: capsule)
                ]
            ),
            "title / card body must still open Details"
        )
        XCTAssertTrue(
            CalendarLayout.blockContains(
                location: CGPoint(x: viewportX, y: placed.y + 8),
                event: placed,
                columnWidth: columnWidth
            )
        )
    }

    func testHourContentPointDoesNotAddParentOffsetWhenHourContentIsFullWidth() {
        let point = CalendarLayout.hourContentPoint(
            locationInScroll: CGPoint(x: 14 * 220 + 40, y: 70),
            contentOffset: CGPoint(x: 0, y: 200),
            boundsOrigin: .zero,
            hourContentWidth: 35 * 220,
            hourBoundsWidth: 390,
            horizontalContentOffset: 14 * 220
        )
        XCTAssertEqual(point.x, 14 * 220 + 40, accuracy: 0.01)
        XCTAssertEqual(point.y, 270, accuracy: 0.01)
    }

    func testHourContentPointDoesNotDoubleCountWhenLocationIsAlreadyInContentX() {
        let point = CalendarLayout.hourContentPoint(
            locationInScroll: CGPoint(x: 14 * 220 + 40, y: 70),
            contentOffset: CGPoint(x: 0, y: 200),
            boundsOrigin: .zero,
            hourContentWidth: 390,
            hourBoundsWidth: 390,
            horizontalContentOffset: 14 * 220
        )
        XCTAssertEqual(point.x, 14 * 220 + 40, accuracy: 0.01)
    }

    func testHourCanvasHitEmptyHourIsTimedNotAllDay() {
        // `605f886` parked PR3 timed in the all-day header (no 16pt capsule).
        let placed = CalendarLayout.placeTimed(
            [event(time: "06:00", duration: 30)],
            pixelsPerHour: 50
        )
        let columns = [
            CalendarLayout.HourCanvasColumn(dayISO: "2026-09-18", events: []),
            CalendarLayout.HourCanvasColumn(dayISO: "2026-09-19", events: placed)
        ]
        let columnWidth: CGFloat = 220
        let empty = CalendarLayout.hourCanvasHit(
            contentPoint: CGPoint(x: columnWidth + 40, y: 4 * 50 + 10),
            columns: columns,
            columnWidth: columnWidth,
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(empty, .emptyHour(dayISO: "2026-09-19", minutes: 4 * 60))
        let title = CalendarLayout.hourCanvasHit(
            contentPoint: CGPoint(x: columnWidth + 40, y: placed[0].y + 8),
            columns: columns,
            columnWidth: columnWidth,
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(title, .blockBody(taskID: "timed"))
        let capsuleRect = CalendarLayout.durationCapsuleRect(
            columnIndex: 1,
            columnWidth: columnWidth,
            event: placed[0]
        )
        let handle = CalendarLayout.hourCanvasHit(
            contentPoint: CGPoint(x: capsuleRect.midX, y: capsuleRect.midY),
            columns: columns,
            columnWidth: columnWidth,
            pixelsPerHour: 50,
            snap: 15
        )
        guard case .capsule(let target) = handle else {
            return XCTFail("painted capsule must be a duration hit, not all-day")
        }
        XCTAssertEqual(target.taskID, "timed")
        XCTAssertEqual(target.duration, 30, accuracy: 0.01)
    }

    func testBlockFramePointConvertHitsHour7BodyAndCapsule() {
        // `54090ed` title tap on the hour-7 card opened empty-hour composer.
        // Convert scroller bounds → canvas with UIView.convert, then
        // contentOffset, so the point matches CalendarLayout.blockFrame.
        let hourH: CGFloat = 50
        let header: CGFloat = 52
        let scroll = UIScrollView(frame: CGRect(x: 0, y: header, width: 220, height: 400))
        scroll.contentSize = CGSize(width: 220, height: 24 * hourH)
        let canvas = UIView(frame: CGRect(x: 0, y: 0, width: 220, height: 24 * hourH))
        scroll.addSubview(canvas)
        scroll.contentOffset = CGPoint(x: 0, y: 3 * hourH)
        scroll.layoutIfNeeded()

        let placed = CalendarLayout.placeTimed(
            [event(id: "pr3", time: "07:00", duration: 30)],
            pixelsPerHour: 50
        )[0]
        let frame = CalendarLayout.blockFrame(event: placed, columnWidth: 220)
        XCTAssertEqual(frame.minY, 7 * hourH, accuracy: 0.01)

        let titleInCanvas = CGPoint(x: frame.midX, y: frame.minY + 8)
        let titleInScroll = canvas.convert(titleInCanvas, to: scroll)
        let titlePoint = CalendarLayout.blockFramePoint(
            locationInScroll: titleInScroll,
            scroll: scroll,
            headerHeight: header
        )
        XCTAssertEqual(titlePoint.x, titleInCanvas.x, accuracy: 0.5)
        XCTAssertEqual(titlePoint.y, titleInCanvas.y, accuracy: 0.5)

        let columns = [
            CalendarLayout.HourCanvasColumn(dayISO: "2026-09-19", events: [placed])
        ]
        XCTAssertEqual(
            CalendarLayout.hourCanvasHit(
                contentPoint: titlePoint,
                columns: columns,
                columnWidth: 220,
                pixelsPerHour: 50,
                snap: 15
            ),
            .blockBody(taskID: "pr3"),
            "hour-7 title must be Details, not empty-hour create"
        )

        let capsuleInCanvas = CGPoint(x: frame.midX, y: frame.maxY - 4)
        let capsuleInScroll = canvas.convert(capsuleInCanvas, to: scroll)
        let capsulePoint = CalendarLayout.blockFramePoint(
            locationInScroll: capsuleInScroll,
            scroll: scroll,
            headerHeight: header
        )
        guard case .capsule(let target) = CalendarLayout.hourCanvasHit(
            contentPoint: capsulePoint,
            columns: columns,
            columnWidth: 220,
            pixelsPerHour: 50,
            snap: 15
        ) else {
            return XCTFail("hour-7 bottom 16pt must write setDuration")
        }
        XCTAssertEqual(target.taskID, "pr3")

        let emptyInCanvas = CGPoint(x: 40, y: 4 * hourH + 10)
        let emptyInScroll = canvas.convert(emptyInCanvas, to: scroll)
        let emptyPoint = CalendarLayout.blockFramePoint(
            locationInScroll: emptyInScroll,
            scroll: scroll,
            headerHeight: header
        )
        XCTAssertEqual(
            CalendarLayout.hourCanvasHit(
                contentPoint: emptyPoint,
                columns: columns,
                columnWidth: 220,
                pixelsPerHour: 50,
                snap: 15
            ),
            .emptyHour(dayISO: "2026-09-19", minutes: 4 * 60)
        )
    }

    func testBlockFramePointAddsContentOffsetWhenConvertLandsInViewport() {
        // SwiftUI hour scroller: convert onto the scroll view (bounds.origin
        // stays 0). Adding contentOffset puts hour 7 on blockFrame.y.
        let converted = CGPoint(x: 40, y: 7 * 50 + 8 - 3 * 50)
        let point = CalendarLayout.blockFramePoint(
            converted: converted,
            contentOffset: CGPoint(x: 0, y: 3 * 50),
            boundsOrigin: .zero,
            headerHeight: 52,
            canvasSize: CGSize(width: 220, height: 400),
            contentSize: CGSize(width: 220, height: 24 * 50),
            convertedFromScrollView: true
        )
        XCTAssertEqual(point.x, 40, accuracy: 0.01)
        XCTAssertEqual(point.y, 7 * 50 + 8, accuracy: 0.01)
        let placed = CalendarLayout.placeTimed(
            [event(id: "pr3", time: "07:00", duration: 30)],
            pixelsPerHour: 50
        )
        XCTAssertEqual(
            CalendarLayout.hourCanvasHit(
                contentPoint: point,
                columns: [CalendarLayout.HourCanvasColumn(dayISO: "2026-09-19", events: placed)],
                columnWidth: 220,
                pixelsPerHour: 50,
                snap: 15
            ),
            .blockBody(taskID: "pr3")
        )
    }

    func testBlockFramePointAddsOffsetWhenContentCanvasSitsAtOrigin() {
        // SwiftUI: content-sized host at (0,0), bounds.origin stays 0.
        // convert is still viewport; contentOffset maps onto blockFrame.
        let point = CalendarLayout.blockFramePoint(
            converted: CGPoint(x: 40, y: 7 * 50 + 8 - 3 * 50),
            contentOffset: CGPoint(x: 0, y: 3 * 50),
            boundsOrigin: .zero,
            headerHeight: 52,
            canvasSize: CGSize(width: 220, height: 24 * 50),
            contentSize: CGSize(width: 220, height: 24 * 50),
            convertedFromScrollView: false,
            canvasFrameOrigin: .zero
        )
        XCTAssertEqual(point.y, 7 * 50 + 8, accuracy: 0.01)
    }

    func testBlockFramePointDoesNotDoubleCountWhenCanvasIsShiftedByOffset() {
        let point = CalendarLayout.blockFramePoint(
            converted: CGPoint(x: 40, y: 7 * 50 + 8),
            contentOffset: CGPoint(x: 0, y: 3 * 50),
            boundsOrigin: .zero,
            headerHeight: 52,
            canvasSize: CGSize(width: 220, height: 24 * 50),
            contentSize: CGSize(width: 220, height: 24 * 50),
            convertedFromScrollView: false,
            canvasFrameOrigin: CGPoint(x: 0, y: -3 * 50)
        )
        XCTAssertEqual(point.y, 7 * 50 + 8, accuracy: 0.01)
    }

    func testBlockFramePointSubtractsAllDayHeader() {
        // Convert landed on a parent that still includes the sticky all-day
        // row. Subtract headerHeight so y=0 is hour 0 / blockFrame.
        let converted = CGPoint(x: 40, y: 52 + 7 * 50 + 8)
        let point = CalendarLayout.blockFramePoint(
            converted: converted,
            contentOffset: .zero,
            boundsOrigin: .zero,
            headerHeight: 52,
            canvasSize: CGSize(width: 220, height: 52 + 24 * 50),
            contentSize: CGSize(width: 220, height: 24 * 50),
            convertedFromScrollView: false
        )
        XCTAssertEqual(point.y, 7 * 50 + 8, accuracy: 0.01)
        XCTAssertEqual(point.x, 40, accuracy: 0.01)
    }

    func testLiveColumnsExposeJustCreatedHour7Card() {
        // Coordinator struct snapshot at `54090ed` was empty after create.
        // hourCanvasColumns must read the live task list.
        let created = event(id: "pr3", time: "07:00", duration: 30)
        var tasks: [String: [TaskSnapshot]] = ["2026-09-19": []]
        var columns = CalendarLayout.hourCanvasColumns(
            dayISOs: ["2026-09-19"],
            tasksOnDay: { tasks[$0] ?? [] },
            pixelsPerHour: 50
        )
        XCTAssertTrue(columns[0].events.isEmpty)
        tasks["2026-09-19"] = [created]
        columns = CalendarLayout.hourCanvasColumns(
            dayISOs: ["2026-09-19"],
            tasksOnDay: { tasks[$0] ?? [] },
            pixelsPerHour: 50
        )
        let title = CGPoint(x: 40, y: 7 * 50 + 8)
        XCTAssertEqual(
            CalendarLayout.hourCanvasHit(
                contentPoint: title,
                columns: columns,
                columnWidth: 220,
                pixelsPerHour: 50,
                snap: 15
            ),
            .blockBody(taskID: "pr3")
        )
        let capsule = CalendarLayout.durationCapsuleRect(
            columnIndex: 0,
            columnWidth: 220,
            event: columns[0].events[0]
        )
        guard case .capsule = CalendarLayout.hourCanvasHit(
            contentPoint: CGPoint(x: capsule.midX, y: capsule.midY),
            columns: columns,
            columnWidth: 220,
            pixelsPerHour: 50,
            snap: 15
        ) else {
            return XCTFail("live hour-7 capsule must be setDuration")
        }
    }

    func testBlockFrameOriginMatchesPaintedCard() {
        // Spacer layout places the card at this origin (`e2fba41`/`c7a355e`).
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
        let bodyHeight = frame.height - HomeChrome.durationCapsuleHit
        XCTAssertEqual(bodyHeight, 20, accuracy: 0.01)
        XCTAssertEqual(frame.minY + bodyHeight, capsule.minY, accuracy: 0.01)
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
