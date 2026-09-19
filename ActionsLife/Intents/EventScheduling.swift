import Foundation
import SwiftData

enum EventIntentFailure: Error, Equatable, LocalizedError {
    case notSignedIn
    case needsTitle
    case notFound
    case hasChildren(Int)
    case unsupported(String)

    var message: String {
        switch self {
        case .notSignedIn:
            return "Sign in to actions.life first."
        case .needsTitle:
            return "Give the event a name."
        case .notFound:
            return "That event isn’t on your calendar."
        case .hasChildren(let count):
            return "This event has \(count) subtasks. Open it in the app to delete the whole tree."
        case .unsupported(let detail):
            return detail
        }
    }

    var errorDescription: String? { message }
}

enum EventScheduling {
    struct Window: Equatable {
        var dayISO: String
        var startTime: String
        var duration: Double

        var isAllDay: Bool { startTime.isEmpty }
    }

    static func isEvent(startDateISO: String, isTombstone: Bool) -> Bool {
        !isTombstone && !startDateISO.isEmpty
    }

    static func window(
        from start: Date,
        end: Date?,
        isAllDay: Bool,
        defaultDuration: Double = 30
    ) -> Window {
        let dayISO = DateISO.dayString(from: start)
        let duration: Double
        if let end, end > start {
            duration = max(1, end.timeIntervalSince(start) / 60.0)
        } else {
            duration = max(1, defaultDuration)
        }
        if isAllDay {
            return Window(dayISO: dayISO, startTime: "", duration: duration)
        }
        return Window(dayISO: dayISO, startTime: DateISO.timeString(from: start), duration: duration)
    }

    static func dates(dayISO: String, startTime: String, duration: Double) -> (start: Date, end: Date, isAllDay: Bool)? {
        guard let day = DateISO.date(fromDayISO: dayISO) else { return nil }
        let minutes = max(Int(duration.rounded()), 1)
        if startTime.isEmpty {
            let end = Calendar.current.date(byAdding: .minute, value: minutes, to: day) ?? day
            return (day, end, true)
        }
        let startMinutes = DateISO.minutes(fromClock: startTime) ?? 0
        let start = Calendar.current.date(byAdding: .minute, value: startMinutes, to: day) ?? day
        let end = Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start
        return (start, end, false)
    }

    @MainActor
    static func requireSessionStore(container: ModelContainer) throws -> TaskTreeStore {
        guard let session = LocalSessionStore.load() else {
            throw EventIntentFailure.notSignedIn
        }
        if let live = IntentStore.live, live.uid == session.uid {
            return live
        }
        return TaskTreeStore(context: ModelContext(container), uid: session.uid)
    }

    @MainActor
    static func create(
        store: TaskTreeStore,
        title: String,
        start: Date,
        end: Date?,
        isAllDay: Bool,
        notes: String
    ) throws -> TaskRecord {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw EventIntentFailure.needsTitle }
        let window = window(from: start, end: end, isAllDay: isAllDay)
        return store.create(
            name: name,
            onList: false,
            startDateISO: window.dayISO,
            startTime: window.startTime,
            duration: window.duration,
            notes: notes
        )
    }

    @MainActor
    static func update(
        store: TaskTreeStore,
        id: String,
        title: String?,
        start: Date?,
        end: Date?,
        isAllDay: Bool?,
        notes: String?
    ) throws -> TaskRecord {
        guard let record = store.task(id: id), isEvent(startDateISO: record.startDateISO, isTombstone: record.isTombstone) else {
            throw EventIntentFailure.notFound
        }
        if let title {
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw EventIntentFailure.needsTitle }
            store.rename(id, to: name)
        }
        if let notes {
            store.setNotes(id, notes: notes)
        }
        if start != nil || end != nil || isAllDay != nil {
            let current = dates(dayISO: record.startDateISO, startTime: record.startTime, duration: record.duration)
            let nextStart = start ?? current?.start ?? .now
            let nextAllDay = isAllDay ?? current?.isAllDay ?? record.startTime.isEmpty
            let nextEnd = end ?? current?.end
            let window = window(from: nextStart, end: nextEnd, isAllDay: nextAllDay, defaultDuration: record.duration)
            store.schedule(id, dayISO: window.dayISO, time: window.startTime, duration: window.duration)
        }
        guard let updated = store.task(id: id) else { throw EventIntentFailure.notFound }
        return updated
    }

    @MainActor
    static func deleteLeaf(store: TaskTreeStore, id: String) throws {
        guard let record = store.task(id: id), isEvent(startDateISO: record.startDateISO, isTombstone: record.isTombstone) else {
            throw EventIntentFailure.notFound
        }
        let childCount = store.children(of: id).count
        guard childCount == 0 else { throw EventIntentFailure.hasChildren(childCount) }
        store.deleteSubtree(id)
    }
}

@MainActor
enum IntentStore {
    static weak var live: TaskTreeStore?
}
