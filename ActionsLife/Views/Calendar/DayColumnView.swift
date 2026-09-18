import SwiftUI

struct DayColumnView: View {
    @Bindable var store: TaskTreeStore
    let day: Date
    let tasks: [TaskSnapshot]
    let pixelsPerHour: Double
    let columnWidth: CGFloat
    @Binding var selectedTaskID: String?
    @Environment(HomeChrome.self) private var chrome

    private var hourHeight: CGFloat { CalendarLayout.hourHeight(pixelsPerHour: pixelsPerHour) }
    private var canvasHeight: CGFloat { CalendarLayout.canvasHeight(pixelsPerHour: pixelsPerHour) }
    private var split: (allDay: [TaskSnapshot], timed: [TaskSnapshot]) { CalendarLayout.split(tasks: tasks) }
    private var placed: [CalendarLayout.PlacedEvent] {
        CalendarLayout.placeTimed(split.timed, pixelsPerHour: pixelsPerHour)
    }
    private var dayISO: String { DateISO.dayString(from: day) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            timedCanvas
        }
        .frame(width: columnWidth)
        .background(Theme.calendarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.grid)
                .frame(width: 1)
        }
        .accessibilityLabel("Schedule for \(dayISO)")
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 4) {
                Text(day, format: .dateTime.weekday(.abbreviated))
                Text(day, format: .dateTime.day())
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                ForEach(split.allDay) { task in
                    CalendarEventCard(
                        task: task,
                        children: store.children(of: task.id),
                        compact: true,
                        onToggle: { store.toggleDone(task.id) },
                        onOpen: { selectedTaskID = task.id }
                    )
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            store.schedule(id, dayISO: dayISO, time: "")
            return true
        } isTargeted: { chrome.setDropTargeted($0) }
    }

    private var timedCanvas: some View {
        ZStack(alignment: .topLeading) {
            hourGrid
            ForEach(placed) { event in
                CalendarEventCard(
                    task: event.task,
                    children: store.children(of: event.task.id),
                    onToggle: { store.toggleDone(event.task.id) },
                    onOpen: { selectedTaskID = event.task.id }
                )
                .frame(height: max(event.height, 36), alignment: .top)
                .padding(.horizontal, 6)
                .offset(y: event.y)
            }
            if isToday {
                nowIndicator
            }
        }
        .frame(width: columnWidth, height: canvasHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, location in
            guard let id = ids.first else { return false }
            let snap = max(Int(store.profile?.calSnapInterval ?? 15), 5)
            let minutes = CalendarLayout.minutes(atY: location.y, pixelsPerHour: pixelsPerHour, snap: snap)
            store.schedule(id, dayISO: dayISO, time: CalendarLayout.clock(fromMinutes: minutes))
            return true
        } isTargeted: { chrome.setDropTargeted($0) }
        .allowsHitTesting(!chrome.isResizing)
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(CalendarLayout.hours(), id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.grid)
                        .frame(height: 1)
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight)
            }
        }
    }

    private var nowIndicator: some View {
        let y = CalendarLayout.nowY(pixelsPerHour: pixelsPerHour)
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: y)
            Rectangle()
                .fill(Theme.now)
                .frame(height: 2)
            Text(Date.now, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.now)
                .padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .frame(height: canvasHeight, alignment: .top)
        .allowsHitTesting(false)
    }
}
