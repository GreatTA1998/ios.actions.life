import CoreGraphics
import XCTest
@testable import ActionsLife

final class DragDropTests: XCTestCase {
    func testCanvasYIgnoresScrollByUsingGlobalFrame() {
        // Canvas has been scrolled so its global top is -400. 10:00 is at local y 500.
        let canvasMinY: CGFloat = -400
        let tenAMGlobalY: CGFloat = -400 + 500
        let localY = DropMath.canvasY(globalY: tenAMGlobalY, canvasGlobalMinY: canvasMinY)
        XCTAssertEqual(localY, 500)
        XCTAssertEqual(CalendarLayout.minutes(atY: localY, pixelsPerHour: 50, snap: 15), 10 * 60)
    }

    func testSameVisiblePointMapsDifferentlyWhenScrolledIfYouForgetTheFrame() {
        let visibleY: CGFloat = 200
        let unscrolled = CalendarLayout.minutes(atY: visibleY, pixelsPerHour: 50, snap: 15)
        let scrolledLocal = DropMath.canvasY(globalY: visibleY, canvasGlobalMinY: -400)
        let scrolled = CalendarLayout.minutes(atY: scrolledLocal, pixelsPerHour: 50, snap: 15)
        XCTAssertNotEqual(unscrolled, scrolled)
        XCTAssertEqual(scrolled, 12 * 60)
    }

    func testTimedZoneBeatsHeaderAndList() {
        let zones = [
            HomeChrome.DropZone(kind: .list, frame: CGRect(x: 0, y: 600, width: 400, height: 400)),
            HomeChrome.DropZone(kind: .allDay("2026-09-18"), frame: CGRect(x: 40, y: 0, width: 200, height: 80)),
            HomeChrome.DropZone(kind: .timed("2026-09-18"), frame: CGRect(x: 40, y: 80, width: 200, height: 1200))
        ]
        let target = DropMath.target(
            ghostTop: CGPoint(x: 80, y: 80 + 500),
            ghostSize: CGSize(width: 160, height: 40),
            zones: zones,
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .timed(dayISO: "2026-09-18", minutes: 10 * 60))
    }

    func testHeaderDropIsAllDay() {
        let zones = [
            HomeChrome.DropZone(kind: .allDay("2026-09-18"), frame: CGRect(x: 40, y: 0, width: 200, height: 80)),
            HomeChrome.DropZone(kind: .timed("2026-09-18"), frame: CGRect(x: 40, y: 80, width: 200, height: 1200))
        ]
        let target = DropMath.target(
            ghostTop: CGPoint(x: 80, y: 20),
            ghostSize: CGSize(width: 160, height: 36),
            zones: zones,
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
            ghostSize: CGSize(width: 200, height: 36),
            zones: zones,
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .listSlot(parentID: "", index: 2))
    }

    func testNestBeatsTimedCanvas() {
        let zones = [
            HomeChrome.DropZone(kind: .timed("2026-09-18"), frame: CGRect(x: 40, y: 80, width: 200, height: 1200)),
            HomeChrome.DropZone(kind: .nest("parent-1"), frame: CGRect(x: 48, y: 300, width: 180, height: 48))
        ]
        let target = DropMath.target(
            ghostTop: CGPoint(x: 80, y: 310),
            ghostSize: CGSize(width: 160, height: 40),
            zones: zones,
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .nest("parent-1"))
    }

    func testListDropUnscheduleTarget() {
        let zones = [
            HomeChrome.DropZone(kind: .list, frame: CGRect(x: 0, y: 400, width: 400, height: 400)),
            HomeChrome.DropZone(kind: .timed("2026-09-18"), frame: CGRect(x: 40, y: 0, width: 200, height: 380))
        ]
        let target = DropMath.target(
            ghostTop: CGPoint(x: 40, y: 480),
            ghostSize: CGSize(width: 200, height: 36),
            zones: zones,
            pixelsPerHour: 50,
            snap: 15
        )
        XCTAssertEqual(target, .list)
    }
}
