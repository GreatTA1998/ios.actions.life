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

    private var pixelsPerHour: Double { store.profile?.pixelsPerHour ?? 50 }
    private var hourHeight: CGFloat { CalendarLayout.hourHeight(pixelsPerHour: pixelsPerHour) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            calendarScroll
            stickyTimeAxis
            topChrome
        }
        .background(Theme.calendarBackground)
        .scrollDisabled(chrome.isResizing)
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
            .scrollDisabled(chrome.isResizing)
            .modifier(ScrollOffsetTracker(offset: $scrollOffset))
            .onAppear {
                proxy.scrollTo(DateISO.dayString(from: selectedDay), anchor: .topLeading)
            }
            .onChange(of: selectedDay) { _, day in
                proxy.scrollTo(DateISO.dayString(from: day), anchor: .topLeading)
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
        let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)) ?? .now
        return (0..<21).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
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
