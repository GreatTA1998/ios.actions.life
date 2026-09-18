import SwiftUI

struct DayCalendarView: View {
    @Bindable var store: TaskTreeStore
    @Binding var selectedDay: Date
    @Binding var selectedTaskID: String?
    var columnWidth: CGFloat
    var onJumpToday: () -> Void
    var onMenu: () -> Void

    @Environment(HomeChrome.self) private var chrome
    private let calendar = Calendar.current
    @State private var scrollOffset: CGPoint = .zero
    @State private var pastCount = 14
    @State private var futureCount = 21
    @State private var scrolledDayID: String?

    private var pixelsPerHour: Double { store.profile?.pixelsPerHour ?? 50 }
    private var hourHeight: CGFloat { CalendarLayout.hourHeight(pixelsPerHour: pixelsPerHour) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            calendarScroll
            stickyTimeAxis
            topChrome
        }
        .background(Theme.calendarBackground)
    }

    private var calendarScroll: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: CalendarLayout.timeAxisWidth)
                    ForEach(days, id: \.self) { day in
                        DayColumnView(
                            store: store,
                            day: day,
                            tasks: store.tasks(on: DateISO.dayString(from: day)),
                            pixelsPerHour: pixelsPerHour,
                            columnWidth: columnWidth,
                            selectedTaskID: $selectedTaskID
                        )
                        .id(DateISO.dayString(from: day))
                    }
                }
            }
            .scrollDisabled(chrome.pointerCaptured)
            .scrollPosition(id: $scrolledDayID)
            .modifier(ScrollOffsetTracker(offset: $scrollOffset))
            .onAppear {
                scrolledDayID = DateISO.dayString(from: selectedDay)
                proxy.scrollTo(DateISO.dayString(from: selectedDay), anchor: .topLeading)
            }
            .onChange(of: selectedDay) { _, day in
                scrolledDayID = DateISO.dayString(from: day)
                proxy.scrollTo(DateISO.dayString(from: day), anchor: .topLeading)
            }
            .onChange(of: scrollOffset) { _, _ in
                expandDayWindowIfNeeded()
            }
        }
    }

    private var stickyTimeAxis: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(0, 44 - scrollOffset.y))
            VStack(spacing: 0) {
                ForEach(CalendarLayout.hours(), id: \.self) { hour in
                    Text(CalendarLayout.hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: CalendarLayout.timeAxisWidth - 6, height: hourHeight, alignment: .topTrailing)
                }
            }
            .offset(y: -max(0, scrollOffset.y - 44))
        }
        .frame(width: CalendarLayout.timeAxisWidth, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
        .background(Theme.calendarBackground.opacity(0.92))
    }

    private var topChrome: some View {
        HStack {
            Button("Today", action: onJumpToday)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.86), in: Capsule())
                .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
            Spacer()
            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.86), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var days: [Date] {
        CalendarLayout.dayWindow(past: pastCount, future: futureCount, calendar: calendar)
    }

    private func expandDayWindowIfNeeded() {
        let column = columnWidth
        guard column > 0 else { return }
        let dayIndex = Int((max(scrollOffset.x, 0) / column).rounded(.down))
        if dayIndex <= 1, pastCount < 180 {
            if scrolledDayID == nil, days.indices.contains(max(dayIndex, 0)) {
                scrolledDayID = DateISO.dayString(from: days[max(dayIndex, 0)])
            }
            pastCount += 14
        }
        if dayIndex >= days.count - 4, futureCount < 180 {
            futureCount += 14
        }
    }
}

private struct ScrollOffsetTracker: ViewModifier {
    @Binding var offset: CGPoint

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGPoint.self) { geo in
                geo.contentOffset
            } action: { _, newValue in
                offset = newValue
            }
        } else {
            content
        }
    }
}
