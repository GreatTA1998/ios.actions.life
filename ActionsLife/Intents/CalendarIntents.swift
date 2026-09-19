import AppIntents
import CoreSpotlight
import SwiftData

struct EventEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Event")
    static var defaultQuery = EventEntityQuery()

    var id: String
    var title: String
    var dayISO: String
    var startTime: String
    var duration: Double
    var notes: String

    var startDate: Date {
        EventScheduling.dates(dayISO: dayISO, startTime: startTime, duration: duration)?.start ?? .now
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: String
        if startTime.isEmpty {
            subtitle = dayISO
        } else {
            subtitle = "\(dayISO) \(startTime)"
        }
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title.isEmpty ? "Untitled" : title),
            subtitle: LocalizedStringResource(stringLiteral: subtitle)
        )
    }

    static func make(from record: TaskRecord) -> EventEntity? {
        make(
            id: record.id,
            name: record.name,
            startDateISO: record.startDateISO,
            startTime: record.startTime,
            duration: record.duration,
            notes: record.notes,
            isTombstone: record.isTombstone
        )
    }

    static func make(from snapshot: TaskSnapshot) -> EventEntity? {
        make(
            id: snapshot.id,
            name: snapshot.name,
            startDateISO: snapshot.startDateISO,
            startTime: snapshot.startTime,
            duration: snapshot.duration,
            notes: snapshot.notes,
            isTombstone: false
        )
    }

    private static func make(
        id: String,
        name: String,
        startDateISO: String,
        startTime: String,
        duration: Double,
        notes: String,
        isTombstone: Bool
    ) -> EventEntity? {
        guard EventScheduling.isEvent(startDateISO: startDateISO, isTombstone: isTombstone) else { return nil }
        return EventEntity(
            id: id,
            title: name,
            dayISO: startDateISO,
            startTime: startTime,
            duration: duration,
            notes: notes
        )
    }
}

@available(iOS 18.0, *)
extension EventEntity: IndexedEntity {}

struct EventEntityQuery: EntityQuery {
    @Dependency var container: ModelContainer

    func entities(for identifiers: [EventEntity.ID]) async throws -> [EventEntity] {
        try await MainActor.run {
            let store = try EventScheduling.requireSessionStore(container: container)
            return identifiers.compactMap { id in
                store.task(id: id).flatMap(EventEntity.make)
            }
        }
    }

    func suggestedEntities() async throws -> [EventEntity] {
        try await MainActor.run {
            let store = try EventScheduling.requireSessionStore(container: container)
            let today = DateISO.dayString(from: .now)
            return store.tasks(on: today).compactMap(EventEntity.make)
        }
    }
}

extension EventEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [EventEntity] {
        try await MainActor.run {
            let store = try EventScheduling.requireSessionStore(container: container)
            let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return store.allSnapshots.compactMap(EventEntity.make).filter { entity in
                needle.isEmpty
                    || entity.title.lowercased().contains(needle)
                    || entity.notes.lowercased().contains(needle)
            }
        }
    }
}

struct CreateEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Schedule Event"
    static var description = IntentDescription("Adds a timed or all-day event to your actions.life calendar.")
    static var openAppWhenRun = false

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "When")
    var startDate: Date

    @Parameter(title: "End")
    var endDate: Date?

    @Parameter(title: "All-day", default: false)
    var isAllDay: Bool

    @Parameter(title: "Notes", default: "")
    var notes: String

    @Dependency var container: ModelContainer

    init() {
        title = ""
        startDate = .now
        endDate = nil
        isAllDay = false
        notes = ""
    }

    init(title: String, startDate: Date, endDate: Date? = nil, isAllDay: Bool = false, notes: String = "") {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.notes = notes
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<EventEntity> & ProvidesDialog {
        let store = try EventScheduling.requireSessionStore(container: container)
        let record = try EventScheduling.create(
            store: store,
            title: title,
            start: startDate,
            end: endDate,
            isAllDay: isAllDay,
            notes: notes
        )
        guard let entity = EventEntity.make(from: record) else {
            throw EventIntentFailure.notFound
        }
        let when = entity.startTime.isEmpty ? entity.dayISO : "\(entity.dayISO) at \(entity.startTime)"
        return .result(
            value: entity,
            dialog: IntentDialog(stringLiteral: "Scheduled \(entity.title) for \(when).")
        )
    }
}

struct ListDayEventsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Events"
    static var description = IntentDescription("Lists scheduled actions.life events for a day.")
    static var openAppWhenRun = false

    @Parameter(title: "Day")
    var day: Date

    @Dependency var container: ModelContainer

    init() {
        day = .now
    }

    init(day: Date) {
        self.day = day
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = try EventScheduling.requireSessionStore(container: container)
        let dayISO = DateISO.dayString(from: day)
        let events = store.tasks(on: dayISO)
        if events.isEmpty {
            return .result(value: "", dialog: "You have no events on \(dayISO).")
        }
        let lines = events.map { task in
            let name = task.name.isEmpty ? "Untitled" : task.name
            if task.startTime.isEmpty {
                return "All day: \(name)"
            }
            return "\(task.startTime) \(name)"
        }
        return .result(
            value: lines.joined(separator: "\n"),
            dialog: IntentDialog(stringLiteral: lines.joined(separator: ", "))
        )
    }
}

struct UpdateEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Update Event"
    static var description = IntentDescription("Changes the title, time, or notes of a scheduled event.")
    static var openAppWhenRun = false

    @Parameter(title: "Event")
    var event: EventEntity

    @Parameter(title: "New title")
    var title: String?

    @Parameter(title: "When")
    var startDate: Date?

    @Parameter(title: "End")
    var endDate: Date?

    @Parameter(title: "All-day")
    var isAllDay: Bool?

    @Parameter(title: "Notes")
    var notes: String?

    @Dependency var container: ModelContainer

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<EventEntity> & ProvidesDialog {
        let store = try EventScheduling.requireSessionStore(container: container)
        let record = try EventScheduling.update(
            store: store,
            id: event.id,
            title: title,
            start: startDate,
            end: endDate,
            isAllDay: isAllDay,
            notes: notes
        )
        guard let entity = EventEntity.make(from: record) else {
            throw EventIntentFailure.notFound
        }
        return .result(value: entity, dialog: "Updated \(entity.title).")
    }
}

struct DeleteEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete Event"
    static var description = IntentDescription("Deletes a scheduled event that has no subtasks.")
    static var openAppWhenRun = false

    @Parameter(title: "Event")
    var event: EventEntity

    @Dependency var container: ModelContainer

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try EventScheduling.requireSessionStore(container: container)
        try EventScheduling.deleteLeaf(store: store, id: event.id)
        let name = event.title.isEmpty ? "Untitled" : event.title
        return .result(dialog: "Deleted \(name).")
    }
}

struct OpenEventIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Event"
    static var openAppWhenRun = true

    @Parameter(title: "Event")
    var target: EventEntity

    @Dependency var navigation: AppNavigation

    @MainActor
    func perform() async throws -> some IntentResult {
        navigation.open(taskID: target.id, dayISO: target.dayISO)
        return .result()
    }
}

struct ActionsLifeShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .forestGreen

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateEventIntent(),
            phrases: [
                "Schedule an event in \(.applicationName)",
                "Create an event in \(.applicationName)",
                "Add an event to \(.applicationName)"
            ],
            shortTitle: "Schedule event",
            systemImageName: "calendar.badge.plus"
        ),
        AppShortcut(
            intent: ListDayEventsIntent(),
            phrases: [
                "What events do I have in \(.applicationName)",
                "What's on my \(.applicationName) calendar today"
            ],
            shortTitle: "Today's events",
            systemImageName: "calendar"
        )
    }
}

enum EventIndex {
    @MainActor
    private static var indexedIDs: Set<String> = []

    @MainActor
    static func scheduleSync(snapshots: [TaskSnapshot]) {
        let copy = snapshots
        Task { await sync(snapshots: copy) }
    }

    @MainActor
    static func sync(snapshots: [TaskSnapshot]) async {
        guard #available(iOS 18.0, *) else { return }
        let entities = snapshots.compactMap(EventEntity.make)
        let nextIDs = Set(entities.map(\.id))
        let removed = indexedIDs.subtracting(nextIDs)
        let index = CSSearchableIndex.default()
        if !removed.isEmpty {
            try? await index.deleteAppEntities(identifiedBy: Array(removed), ofType: EventEntity.self)
        }
        if !entities.isEmpty {
            try? await index.indexAppEntities(entities)
        }
        indexedIDs = nextIDs
    }
}
