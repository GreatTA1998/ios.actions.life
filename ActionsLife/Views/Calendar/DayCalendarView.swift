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
    @State private var dayScrollX: CGFloat = 0
    @State private var hourScrollY: CGFloat = 0
    @State private var pastCount = 14
    @State private var futureCount = 21
    @State private var nowScrollGeneration = 0
    @State private var headerHeight: CGFloat = 52

    private var pixelsPerHour: Double { store.profile?.pixelsPerHour ?? 50 }
    private var hourHeight: CGFloat { CalendarLayout.hourHeight(pixelsPerHour: pixelsPerHour) }

    var body: some View {
        VStack(spacing: 0) {
            chromeRow
            GeometryReader { geo in
                let timedHeight = max(80, geo.size.height - headerHeight)
                HStack(alignment: .top, spacing: 0) {
                    timeGutter(timedHeight: timedHeight)
                    dayStrip(height: geo.size.height, timedHeight: timedHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.calendarBackground)
        .onPreferenceChange(CalendarHeaderHeightKey.self) { headerHeight = max($0, 44) }
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

    /// Hour labels sit outside the day strip so a horizontal day jump cannot
    /// translate them (b956880 put Today/hours at x≈3070).
    private func timeGutter(timedHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: CalendarLayout.timeAxisWidth, height: headerHeight)
            VStack(spacing: 0) {
                ForEach(CalendarLayout.hours(), id: \.self) { hour in
                    Text(CalendarLayout.hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: CalendarLayout.timeAxisWidth - 6, height: hourHeight, alignment: .topTrailing)
                }
            }
            .offset(y: -hourScrollY)
            .frame(width: CalendarLayout.timeAxisWidth, height: timedHeight, alignment: .top)
            .clipped()
            .background(Theme.calendarBackground.opacity(0.92))
        }
        .allowsHitTesting(false)
    }

    /// Horizontal day scroller (headers + canvases). Hours are a nested
    /// vertical-only scroller — never `ScrollView([.horizontal, .vertical])`.
    private func dayStrip(height: CGFloat, timedHeight: CGFloat) -> some View {
        ScrollViewReader { hProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    hourScroll(timedHeight: timedHeight)
                }
                .frame(height: height, alignment: .top)
            }
            .scrollDisabled(chrome.pointerCaptured)
            .modifier(ScrollOffsetTracker { dayScrollX = $0.x })
            .onAppear { scrollDays(hProxy) }
            .onChange(of: selectedDay) { _, _ in scrollDays(hProxy) }
            .onChange(of: nowScrollGeneration) { _, _ in scrollDays(hProxy) }
            .onChange(of: dayScrollX) { _, _ in expandDayWindowIfNeeded() }
        }
    }

    /// In the horizontal scroller so it stays on-screen in Y and tracks days in X.
    private var headerRow: some View {
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
                .id(DateISO.dayString(from: day))
            }
        }
        .background(Theme.calendarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.grid)
                .frame(height: 1)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: CalendarHeaderHeightKey.self, value: geo.size.height)
            }
        }
    }

    private func hourScroll(timedHeight: CGFloat) -> some View {
        let treeStore = store
        let homeChrome = chrome
        let dayISOs = days.map { DateISO.dayString(from: $0) }
        let pixels = pixelsPerHour
        return ScrollViewReader { vProxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            DayColumnView(
                                store: treeStore,
                                day: day,
                                tasks: treeStore.tasks(on: DateISO.dayString(from: day)),
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
                    // Leading edge of the hour canvas — never at todayIndex×columnWidth.
                    VStack(spacing: 0) {
                        Color.clear.frame(height: CalendarLayout.nowScrollY(pixelsPerHour: pixelsPerHour))
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id("now-y")
                        Spacer(minLength: 0)
                    }
                    .frame(width: 1, height: CalendarLayout.canvasHeight(pixelsPerHour: pixelsPerHour))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    ScrollToYBridge(
                        y: CalendarLayout.nowScrollY(pixelsPerHour: pixelsPerHour),
                        generation: nowScrollGeneration
                    )
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    HourScrollTouchBridge()
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    // Tap + capsule pan on the hour scroller (`605f886` pan-only
                    // ate SpatialTap, so empty-hour create went all-day).
                    HourDurationPanBridge(
                        enabled: homeChrome.drag == nil && !homeChrome.isResizing,
                        liveColumns: {
                            CalendarLayout.hourCanvasColumns(
                                dayISOs: dayISOs,
                                tasksOnDay: { treeStore.tasks(on: $0) },
                                pixelsPerHour: pixels,
                                previewTaskID: homeChrome.durationResize?.taskID,
                                previewDuration: homeChrome.durationResize?.previewDuration
                            )
                        },
                        headerHeight: headerHeight,
                        columnWidth: columnWidth,
                        pixelsPerHour: pixelsPerHour,
                        snap: homeChrome.snapInterval,
                        onTimedCreate: { dayISO, minutes in
                            guard homeChrome.durationResize == nil, homeChrome.drag == nil else { return }
                            composerText = ""
                            calendarComposer = .timed(dayISO: dayISO, minutes: minutes)
                        },
                        onOpenDetails: { taskID in
                            guard homeChrome.durationResize == nil, homeChrome.drag == nil else { return }
                            selectedTaskID = taskID
                        },
                        onBegan: { hit in
                            homeChrome.beginDurationResize(taskID: hit.taskID, duration: hit.duration)
                        },
                        onChanged: { homeChrome.moveDurationResize(deltaY: $0) },
                        onEnded: {
                            if let result = homeChrome.finishDurationResize() {
                                treeStore.setDuration(result.taskID, minutes: result.duration)
                            }
                        },
                        onCancel: { homeChrome.cancelDurationResize() }
                    )
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    ScrollOffsetLockBridge(locked: homeChrome.durationResize != nil)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: timedHeight)
            .scrollDisabled(homeChrome.pointerCaptured)
            .modifier(ScrollOffsetTracker { hourScrollY = $0.y })
            .onAppear { jumpHours(vProxy) }
            .onChange(of: nowScrollGeneration) { _, _ in jumpHours(vProxy) }
            .task {
                try? await Task.sleep(nanoseconds: 80_000_000)
                jumpHours(vProxy)
                try? await Task.sleep(nanoseconds: 250_000_000)
                jumpHours(vProxy)
            }
        }
    }

    private var days: [Date] {
        CalendarLayout.dayWindow(past: pastCount, future: futureCount, calendar: calendar)
    }

    private func scrollDays(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(DateISO.dayString(from: selectedDay), anchor: .leading)
        if nowScrollGeneration == 0 {
            nowScrollGeneration = 1
        }
    }

    private func jumpHours(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("now-y", anchor: .top)
        if nowScrollGeneration == 0 {
            nowScrollGeneration = 1
        }
    }

    private func expandDayWindowIfNeeded() {
        guard nowScrollGeneration > 0 else { return }
        let column = columnWidth
        guard column > 0 else { return }
        let dayIndex = Int((max(dayScrollX, 0) / column).rounded(.down))
        if dayIndex <= 1, pastCount < 180 {
            pastCount += 14
        }
        if dayIndex >= days.count - 4, futureCount < 180 {
            futureCount += 14
        }
    }
}

private struct CalendarHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 52
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ScrollOffsetTracker: ViewModifier {
    var onChange: (CGPoint) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGPoint.self) { geo in
                geo.contentOffset
            } action: { _, newValue in
                onChange(newValue)
            }
        } else {
            content
        }
    }
}
