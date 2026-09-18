import SwiftUI

struct DayCalendarView: View {
    @Bindable var store: TaskTreeStore
    @Binding var selectedDay: Date
    @Binding var selectedTaskID: String?
    @Binding var calendarComposer: CalendarComposer?
    @Binding var composerText: String
    var onCommitComposer: () -> Void
    var onCancelComposer: () -> Void
    var columnWidth: CGFloat
    var onJumpToday: () -> Void
    var onMenu: () -> Void

    @Environment(HomeChrome.self) private var chrome
    private let calendar = Calendar.current
    @State private var scrollOffset: CGPoint = .zero
    @State private var pastCount = 14
    @State private var futureCount = 21
    @State private var nowScrollGeneration = 0

    private var pixelsPerHour: Double { store.profile?.pixelsPerHour ?? 50 }
    private var hourHeight: CGFloat { CalendarLayout.hourHeight(pixelsPerHour: pixelsPerHour) }

    var body: some View {
        VStack(spacing: 0) {
            chromeRow
            dayHeaderStrip
            timedPane
        }
        .background(Theme.calendarBackground)
    }

    private var chromeRow: some View {
        HStack {
            Button("Today") {
                onJumpToday()
                nowScrollGeneration += 1
            }
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
        .padding(.vertical, 6)
        .background(Theme.calendarBackground)
    }

    /// Real layout row (not a ZStack overlay). Overlay headers never appeared on Simulator.
    private var dayHeaderStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: CalendarLayout.timeAxisWidth)
            HStack(alignment: .top, spacing: 0) {
                ForEach(days, id: \.self) { day in
                    DayColumnView(
                        store: store,
                        day: day,
                        tasks: store.tasks(on: DateISO.dayString(from: day)),
                        pixelsPerHour: pixelsPerHour,
                        columnWidth: columnWidth,
                        selectedTaskID: $selectedTaskID,
                        calendarComposer: $calendarComposer,
                        composerText: $composerText,
                        onCommitComposer: onCommitComposer,
                        onCancelComposer: onCancelComposer,
                        showsHeader: true,
                        showsTimedCanvas: false
                    )
                }
            }
            .offset(x: -scrollOffset.x)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .background(Theme.calendarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.grid)
                .frame(height: 1)
        }
    }

    private var timedPane: some View {
        ZStack(alignment: .topLeading) {
            timedScroll
            stickyTimeAxis
        }
    }

    private var timedScroll: some View {
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
                            selectedTaskID: $selectedTaskID,
                            calendarComposer: $calendarComposer,
                            composerText: $composerText,
                            onCommitComposer: onCommitComposer,
                            onCancelComposer: onCancelComposer,
                            showsHeader: false,
                            showsTimedCanvas: true
                        )
                    }
                }
                .overlay(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: CalendarLayout.nowScrollY(pixelsPerHour: pixelsPerHour))
                        HStack(spacing: 0) {
                            Color.clear.frame(
                                width: CalendarLayout.timeAxisWidth + CGFloat(todayIndex) * columnWidth
                            )
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("jump-now")
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)
                }
                .background {
                    ScrollToOffsetBridge(offset: nowOffset, generation: nowScrollGeneration)
                }
            }
            .scrollDisabled(chrome.pointerCaptured)
            .modifier(ScrollOffsetTracker(offset: $scrollOffset))
            .onAppear { jumpToNow(proxy) }
            .onChange(of: nowScrollGeneration) { _, _ in
                jumpToNow(proxy)
            }
            .onChange(of: scrollOffset) { _, _ in
                expandDayWindowIfNeeded()
            }
            .task {
                try? await Task.sleep(nanoseconds: 80_000_000)
                jumpToNow(proxy)
                try? await Task.sleep(nanoseconds: 250_000_000)
                jumpToNow(proxy)
            }
        }
    }

    private var stickyTimeAxis: some View {
        VStack(spacing: 0) {
            ForEach(CalendarLayout.hours(), id: \.self) { hour in
                Text(CalendarLayout.hourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: CalendarLayout.timeAxisWidth - 6, height: hourHeight, alignment: .topTrailing)
            }
        }
        .offset(y: -scrollOffset.y)
        .frame(width: CalendarLayout.timeAxisWidth, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
        .background(Theme.calendarBackground.opacity(0.92))
    }

    private var days: [Date] {
        CalendarLayout.dayWindow(past: pastCount, future: futureCount, calendar: calendar)
    }

    private var todayIndex: Int {
        days.firstIndex { calendar.isDateInToday($0) } ?? pastCount
    }

    private var nowOffset: CGPoint {
        CalendarLayout.timedContentOffset(
            todayIndex: todayIndex,
            columnWidth: columnWidth,
            pixelsPerHour: pixelsPerHour
        )
    }

    private func jumpToNow(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("jump-now", anchor: .top)
        if nowScrollGeneration == 0 {
            nowScrollGeneration = 1
        }
    }

    private func expandDayWindowIfNeeded() {
        let column = columnWidth
        guard column > 0 else { return }
        let dayIndex = Int((max(scrollOffset.x, 0) / column).rounded(.down))
        if dayIndex <= 1, pastCount < 180 {
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
