import SwiftData
import SwiftUI

struct HomeView: View {
    let uid: String
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var auth

    @State private var store: TaskTreeStore?
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var selectedTaskID: String?
    @State private var composerText = ""
    @State private var composer: ComposerSlot?
    @State private var calendarComposer: CalendarComposer?
    @State private var showMenu = false
    @State private var chrome = HomeChrome()
    /// Local split while dragging the handle (Expo SplitPane `visual`).
    @State private var visualSplit: Double?
    @State private var splitDragStart: Double = 0.5
    @State private var edgeTick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    GeometryReader { geo in
                        let split = visualSplit ?? store.listHeightSplit
                        let handle = HomeChrome.splitHandle
                        let remaining = max(1, geo.size.height - handle)
                        let listHeight = remaining * split
                        let calendarHeight = remaining - listHeight
                        let columnWidth = min(
                            max(store.profile?.calColumnWidth ?? 220, 180),
                            geo.size.width - CalendarLayout.timeAxisWidth - 20
                        )
                        VStack(spacing: 0) {
                            DayCalendarView(
                                store: store,
                                selectedDay: $selectedDay,
                                selectedTaskID: $selectedTaskID,
                                calendarComposer: $calendarComposer,
                                composerText: $composerText,
                                onCommitComposer: { commitComposer(store) },
                                onCancelComposer: cancelComposer,
                                columnWidth: columnWidth,
                                onJumpToday: {
                                    selectedDay = Calendar.current.startOfDay(for: .now)
                                },
                                onMenu: { showMenu = true }
                            )
                            // GeometryReader is under the status bar; pad so Today + day
                            // headers are not hidden (hour 7 was flush under 11:15).
                            .padding(.top, geo.safeAreaInsets.top)
                            .background(Theme.calendarBackground)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(0, calendarHeight))
                            .clipped()
                            .background {
                                PaneFrameReporter(pane: .calendar) { chrome.calendarPane = $0 }
                            }

                            SplitHandle()
                                .frame(height: handle)
                                .overlay {
                                    SplitResizeBridge(
                                        enabled: chrome.drag == nil,
                                        onBegan: {
                                            chrome.isResizing = true
                                            splitDragStart = visualSplit ?? store.listHeightSplit
                                        },
                                        onChanged: { translationY in
                                            let remaining = max(1, geo.size.height - HomeChrome.splitHandle)
                                            let next = HomeChrome.clampSplitFraction(
                                                splitDragStart + Double(translationY / remaining),
                                                height: geo.size.height
                                            )
                                            var transaction = Transaction()
                                            transaction.disablesAnimations = true
                                            withTransaction(transaction) {
                                                visualSplit = next
                                            }
                                        },
                                        onEnded: {
                                            // Always runs on ended/cancelled/failed — never leave
                                            // isResizing stuck (that used to freeze both panes).
                                            chrome.isResizing = false
                                            let value = visualSplit ?? store.listHeightSplit
                                            store.setListHeightSplit(value, height: geo.size.height)
                                            visualSplit = store.listHeightSplit
                                        }
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }

                            InboxView(
                                store: store,
                                selectedTaskID: $selectedTaskID,
                                composer: $composer,
                                composerText: $composerText,
                                onCommitComposer: { commitComposer(store) },
                                onCancelComposer: cancelComposer
                            )
                            .frame(height: max(0, listHeight))
                            .clipped()
                            .background {
                                PaneFrameReporter(pane: .list) { chrome.listPane = $0 }
                            }
                        }
                        .coordinateSpace(name: "homeSplit")
                        .background {
                            PaneFrameReporter(pane: .home) { chrome.homeFrame = $0 }
                        }
                        .onAppear {
                            chrome.pixelsPerHour = store.profile?.pixelsPerHour ?? 50
                            chrome.snapInterval = max(Int(store.profile?.calSnapInterval ?? 15), 5)
                            if visualSplit == nil {
                                visualSplit = HomeChrome.clampSplitFraction(
                                    store.listHeightSplit,
                                    height: geo.size.height
                                )
                            }
                        }
                        .onChange(of: store.listHeightSplit) { _, value in
                            guard !chrome.isResizing else { return }
                            visualSplit = HomeChrome.clampSplitFraction(value, height: geo.size.height)
                        }
                    }
                    .environment(chrome)
                    .onPreferenceChange(DropZonePreferenceKey.self) { chrome.zones = $0 }
                    .onChange(of: composer) { _, value in
                        if value != nil { calendarComposer = nil }
                    }
                    .onChange(of: calendarComposer) { _, value in
                        if value != nil { composer = nil }
                    }
                    .overlay { dragGhost }
                    .onReceive(edgeTick) { _ in
                        guard chrome.drag != nil, let finger = chrome.drag?.finger else { return }
                        chrome.updateEdgeScroll(finger: finger)
                        chrome.moveDrag(finger: finger)
                    }
                    .sheet(item: selectedTaskBinding(store)) { record in
                        TaskDetailSheet(store: store, taskID: record.id)
                    }
                    .confirmationDialog("actions.life", isPresented: $showMenu, titleVisibility: .visible) {
                        Button("Add task") {
                            composerText = ""
                            calendarComposer = nil
                            composer = ComposerSlot(parentID: "", index: store.inbox.count)
                        }
                        Button("Jump to today") {
                            selectedDay = Calendar.current.startOfDay(for: .now)
                        }
                        Button("Sign out", role: .destructive) {
                            auth.signOut()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                    .onChange(of: store.lastScheduledISO) { _, iso in
                        guard let iso, let date = DateISO.date(fromDayISO: iso) else { return }
                        selectedDay = Calendar.current.startOfDay(for: date)
                    }
                } else {
                    Theme.listBackground.ignoresSafeArea()
                }
            }
            .background(Theme.listBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if store == nil {
                let next = TaskTreeStore(context: modelContext, uid: uid)
                next.seedGuestDataIfNeeded()
                store = next
            }
        }
    }

    @ViewBuilder
    private var dragGhost: some View {
        if let drag = chrome.drag {
            GeometryReader { geo in
                let origin = geo.frame(in: .global)
                let top = chrome.ghostTop
                CalendarDropPreview(height: drag.ghostSize.height, dashed: false)
                    .overlay(alignment: .topLeading) {
                        Text(drag.name.isEmpty ? "Untitled" : drag.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .frame(width: drag.ghostSize.width, height: drag.ghostSize.height, alignment: .topLeading)
                    .opacity(0.55)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
                    .offset(x: top.x - origin.minX, y: top.y - origin.minY)
            }
            .allowsHitTesting(false)
        }
    }

    private func commitComposer(_ store: TaskTreeStore) {
        let name = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            if let slot = composer {
                if !slot.parentID.isEmpty {
                    store.setCollapsed(slot.parentID, isCollapsed: false)
                }
                store.create(name: name, parentID: slot.parentID, insertIndex: slot.index)
            } else if let cal = calendarComposer {
                switch cal {
                case .timed(let dayISO, let minutes):
                    store.create(
                        name: name,
                        onList: false,
                        startDateISO: dayISO,
                        startTime: CalendarLayout.clock(fromMinutes: minutes)
                    )
                case .allDay(let dayISO):
                    store.create(
                        name: name,
                        onList: false,
                        startDateISO: dayISO,
                        startTime: ""
                    )
                }
            }
        }
        cancelComposer()
    }

    private func cancelComposer() {
        composerText = ""
        composer = nil
        calendarComposer = nil
    }

    private func selectedTaskBinding(_ store: TaskTreeStore) -> Binding<TaskIdentity?> {
        Binding(
            get: {
                guard let id = selectedTaskID else { return nil }
                return TaskIdentity(id: id)
            },
            set: { selectedTaskID = $0?.id }
        )
    }
}

private struct TaskIdentity: Identifiable {
    var id: String
}

private struct SplitHandle: View {
    var body: some View {
        ZStack {
            Theme.navbarBackground
            VStack(spacing: 3) {
                capsule
                capsule
                capsule
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("Resize list")
    }

    private var capsule: some View {
        Capsule()
            .fill(Theme.handle)
            .frame(width: 22, height: 1.5)
    }
}

struct CalendarDropPreview: View {
    var height: CGFloat
    var dashed = true

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.dragPreview.opacity(0.15))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        Theme.dragPreview.opacity(0.6),
                        style: dashed
                            ? StrokeStyle(lineWidth: 1, dash: [5, 4])
                            : StrokeStyle(lineWidth: 1)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .allowsHitTesting(false)
    }
}
