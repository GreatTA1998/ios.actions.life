import SwiftData
import XCTest
@testable import ActionsLife

@MainActor
final class EventIntentTests: XCTestCase {
    private func makeStore(name: String) throws -> TaskTreeStore {
        let container = Persistence.makeContainer(inMemory: true, name: name)
        let context = ModelContext(container)
        let uid = "siri-user"
        context.insert(UserProfile(uid: uid))
        try context.save()
        return TaskTreeStore(context: context, uid: uid)
    }

    func testWindowMapsTimedAndAllDay() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 17, minute: 0))!
        let timed = EventScheduling.window(from: start, end: nil, isAllDay: false)
        XCTAssertEqual(timed.dayISO, DateISO.dayString(from: start))
        XCTAssertEqual(timed.startTime, DateISO.timeString(from: start))
        XCTAssertEqual(timed.duration, 30)

        let end = start.addingTimeInterval(90 * 60)
        let spanned = EventScheduling.window(from: start, end: end, isAllDay: false)
        XCTAssertEqual(spanned.duration, 90)

        let allDay = EventScheduling.window(from: start, end: nil, isAllDay: true)
        XCTAssertEqual(allDay.startTime, "")
        XCTAssertEqual(allDay.dayISO, "2026-09-19")
    }

    func testInboxTaskIsNotAnEvent() {
        XCTAssertFalse(EventScheduling.isEvent(startDateISO: "", isTombstone: false))
        XCTAssertFalse(EventScheduling.isEvent(startDateISO: "2026-09-19", isTombstone: true))
        XCTAssertTrue(EventScheduling.isEvent(startDateISO: "2026-09-19", isTombstone: false))
    }

    func testCreateMatchesTapCreateDefaults() throws {
        let store = try makeStore(name: "siri-create")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 17, minute: 0))!
        let record = try EventScheduling.create(
            store: store,
            title: "  Dentist  ",
            start: start,
            end: nil,
            isAllDay: false,
            notes: ""
        )
        XCTAssertEqual(record.name, "Dentist")
        XCTAssertEqual(record.startDateISO, DateISO.dayString(from: start))
        XCTAssertEqual(record.startTime, DateISO.timeString(from: start))
        XCTAssertEqual(record.duration, 30)
        XCTAssertFalse(record.onList)
        XCTAssertEqual(store.tasks(on: record.startDateISO).map(\.name), ["Dentist"])
        XCTAssertNotNil(EventEntity.make(from: record))
    }

    func testCreateRejectsBlankTitle() throws {
        let store = try makeStore(name: "siri-blank")
        XCTAssertThrowsError(
            try EventScheduling.create(store: store, title: "   ", start: .now, end: nil, isAllDay: false, notes: "")
        ) { error in
            XCTAssertEqual(error as? EventIntentFailure, .needsTitle)
        }
        XCTAssertTrue(store.tasks(on: DateISO.dayString(from: .now)).isEmpty)
    }

    func testDeleteRefusesSubtree() throws {
        let store = try makeStore(name: "siri-delete")
        let parent = store.create(name: "Lunch", onList: false, startDateISO: "2026-09-19", startTime: "12:00")
        store.addSubtask(under: parent.id, name: "Reserve table")
        XCTAssertThrowsError(try EventScheduling.deleteLeaf(store: store, id: parent.id)) { error in
            XCTAssertEqual(error as? EventIntentFailure, .hasChildren(1))
        }
        XCTAssertNotNil(store.task(id: parent.id))

        let leaf = store.create(name: "Coffee", onList: false, startDateISO: "2026-09-19", startTime: "15:00")
        try EventScheduling.deleteLeaf(store: store, id: leaf.id)
        XCTAssertNil(store.task(id: leaf.id))
    }

    func testListTodayMatchesStore() throws {
        let store = try makeStore(name: "siri-list")
        store.create(name: "Inbox only", onList: true)
        store.create(name: "Standup", onList: false, startDateISO: "2026-09-19", startTime: "09:00")
        XCTAssertEqual(store.tasks(on: "2026-09-19").compactMap(EventEntity.make).map(\.title), ["Standup"])
        XCTAssertNil(EventEntity.make(from: store.inbox.first { $0.task.name == "Inbox only" }!.task))
    }
}
