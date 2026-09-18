import SwiftUI

struct DayColumnView: View {
    @Bindable var store: TaskTreeStore
    let day: Date
    let tasks: [TaskSnapshot]
    let pixelsPerHour: Double
    let columnWidth: CGFloat
    @Binding var selectedTaskID: String?
    @Binding var calendarComposer: CalendarComposer?
    @Binding var composerText: String
    var onCommitComposer: () -> Void
    var onCancelComposer: () -> Void
    var showsHeader: Bool = true
    var showsTimedCanvas: Bool = true
    @Environment(HomeChrome.self) private var chrome

    private var hourHeight: CGFloat { CalendarLayout.hourHeight(pixelsPerHour: pixelsPerHour) }
    private var canvasHeight: CGFloat { CalendarLayout.canvasHeight(pixelsPerHour: pixelsPerHour) }
    private var split: (allDay: [TaskSnapshot], timed: [TaskSnapshot]) { CalendarLayout.split(tasks: tasks) }
    private var placed: [CalendarLayout.PlacedEvent] {
        var timed = split.timed
        if let session = chrome.durationResize,
           let index = timed.firstIndex(where: { $0.id == session.taskID })
        {
            timed[index].duration = session.previewDuration
        }
        return CalendarLayout.placeTimed(timed, pixelsPerHour: pixelsPerHour)
    }
    private var dayISO: String { DateISO.dayString(from: day) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader { header }
            if showsTimedCanvas { timedCanvas }
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
            .contentShape(Rectangle())
            .onTapGesture(perform: beginAllDayComposer)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Add all-day task")

            VStack(spacing: 4) {
                ForEach(split.allDay) { task in
                    CalendarEventCard(
                        task: task,
                        children: store.children(of: task.id),
                        compact: true,
                        onToggle: { store.toggleDone(task.id) },
                        onOpen: { selectedTaskID = task.id },
                        onToggleChild: { store.toggleDone($0) },
                        onDrop: { store.applyDrop($0, taskID: task.id, fromCalendar: true) }
                    )
                }
                if chrome.showsAllDayPreview(for: dayISO) {
                    CalendarDropPreview(height: 12)
                        .padding(.horizontal, 6)
                }
                if case .allDay(let iso) = calendarComposer, iso == dayISO {
                    InlineTaskComposer(
                        text: $composerText,
                        font: .subheadline,
                        onSubmit: onCommitComposer,
                        onCancel: onCancelComposer
                    )
                    .padding(.horizontal, 6)
                    .zIndex(4)
                }
                Color.primary.opacity(0.001)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: beginAllDayComposer)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Add all-day task")
            }
            .padding(.horizontal, 6)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background { DropZoneReporter(kind: .allDay(dayISO)) }
        .contentShape(Rectangle())
    }

    private var timedCanvas: some View {
        ZStack(alignment: .topLeading) {
            hourGrid
            ForEach(placed) { event in
                // Spacer above the card only — never a canvas-height fill (that
                // put capsules on empty hours). Duration drag is a high-priority
                // SwiftUI gesture on the bottom half of this card.
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: max(0, event.y))
                        .allowsHitTesting(false)
                    CalendarEventCard(
                        task: event.task,
                        children: store.children(of: event.task.id),
                        onToggle: { store.toggleDone(event.task.id) },
                        onOpen: { selectedTaskID = event.task.id },
                        onToggleChild: { store.toggleDone($0) },
                        onDrop: { store.applyDrop($0, taskID: event.task.id, fromCalendar: true) },
                        onResizeDuration: { store.setDuration(event.task.id, minutes: $0) },
                        cardHeight: max(event.height, 36)
                    )
                    .frame(width: columnWidth - 12, height: max(event.height, 36), alignment: .top)
                    .padding(.leading, 6)
                }
                .frame(width: columnWidth, alignment: .topLeading)
            }
            if let preview = chrome.timedPreview(for: dayISO) {
                CalendarDropPreview(height: preview.height)
                    .padding(.horizontal, 6)
                    .offset(y: preview.y)
            }
            if case .timed(let iso, let minutes) = calendarComposer, iso == dayISO {
                InlineTaskComposer(
                    text: $composerText,
                    font: .subheadline,
                    onSubmit: onCommitComposer,
                    onCancel: onCancelComposer
                )
                .padding(.horizontal, 6)
                .offset(y: CalendarLayout.y(fromMinutes: minutes, pixelsPerHour: pixelsPerHour))
                .zIndex(8)
            }
            if isToday {
                nowIndicator
            }
        }
        .frame(width: columnWidth, height: canvasHeight, alignment: .topLeading)
        .background { DropZoneReporter(kind: .timed(dayISO)) }
        .contentShape(Rectangle())
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
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { event in
                guard chrome.drag == nil, !chrome.isResizing, chrome.durationResize == nil else { return }
                // Ignore taps that land on a visible block (or its capsule). Empty hours
                // must still open the timed composer — do not use a Y-only test.
                if placed.contains(where: {
                    CalendarLayout.blockContains(location: event.location, event: $0, columnWidth: columnWidth)
                }) {
                    return
                }
                let minutes = CalendarLayout.minutes(
                    atY: event.location.y,
                    pixelsPerHour: pixelsPerHour,
                    snap: chrome.snapInterval
                )
                composerText = ""
                calendarComposer = .timed(dayISO: dayISO, minutes: minutes)
            }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Add timed task")
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

    private func beginAllDayComposer() {
        guard chrome.drag == nil, !chrome.isResizing, chrome.durationResize == nil else { return }
        composerText = ""
        calendarComposer = .allDay(dayISO: dayISO)
    }
}
