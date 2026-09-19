import SwiftData
import SwiftUI

struct HomeView: View {
    let uid: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthSession.self) private var auth
    @Environment(AppNavigation.self) private var navigation

    @State private var store: TaskTreeStore?
    @State private var composerText = ""
    @State private var showComposer = false
    @State private var showMenu = false
    @State private var composerParentID = ""
    @State private var chrome = HomeChrome()

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack {
            Group {
                if let store {
                    GeometryReader { geo in
                        let split = store.listHeightSplit
                        let calendarHeight = max(240, geo.size.height * (1 - split))
                        let columnWidth = min(
                            max(store.profile?.calColumnWidth ?? 220, 180),
                            geo.size.width - CalendarLayout.timeAxisWidth - 20
                        )
                        VStack(spacing: 0) {
                            DayCalendarView(
                                store: store,
                                selectedDay: $navigation.selectedDay,
                                selectedTaskID: $navigation.selectedTaskID,
                                columnWidth: columnWidth,
                                onJumpToday: {
                                    navigation.selectedDay = Calendar.current.startOfDay(for: .now)
                                },
                                onMenu: { showMenu = true }
                            )
                            .frame(height: calendarHeight)
                            .scrollDisabled(chrome.pointerCaptured)
                            .allowsHitTesting(!chrome.isResizing)

                            SplitHandle()
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 0, coordinateSpace: .named("homeSplit"))
                                        .onChanged { value in
                                            chrome.isResizing = true
                                            var transaction = Transaction()
                                            transaction.disablesAnimations = true
                                            withTransaction(transaction) {
                                                store.setListHeightSplitLive(
                                                    1 - value.location.y / geo.size.height
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            chrome.isResizing = false
                                            store.setListHeightSplit(store.listHeightSplit)
                                        }
                                )
                                .allowsHitTesting(chrome.drag == nil)

                            InboxView(
                                store: store,
                                selectedTaskID: $navigation.selectedTaskID,
                                onAddRoot: { showComposer = true; composerParentID = "" },
                                onAddChild: { parent in
                                    composerParentID = parent
                                    showComposer = true
                                }
                            )
                            .frame(maxHeight: .infinity)
                            .scrollDisabled(chrome.pointerCaptured)
                            .allowsHitTesting(!chrome.isResizing)
                        }
                        .coordinateSpace(name: "homeSplit")
                        .onAppear {
                            chrome.pixelsPerHour = store.profile?.pixelsPerHour ?? 50
                            chrome.snapInterval = max(Int(store.profile?.calSnapInterval ?? 15), 5)
                        }
                    }
                    .environment(chrome)
                    .onPreferenceChange(DropZonePreferenceKey.self) { chrome.zones = $0 }
                    .overlay { dragGhost }
                    .sheet(item: selectedTaskBinding(store)) { record in
                        TaskDetailSheet(store: store, taskID: record.id)
                    }
                    .confirmationDialog("actions.life", isPresented: $showMenu, titleVisibility: .visible) {
                        Button("Add task") {
                            composerParentID = ""
                            showComposer = true
                        }
                        Button("Jump to today") {
                            navigation.selectedDay = Calendar.current.startOfDay(for: .now)
                        }
                        Button("Sign out", role: .destructive) {
                            auth.signOut()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                    .onChange(of: store.lastScheduledISO) { _, iso in
                        guard let iso, let date = DateISO.date(fromDayISO: iso) else { return }
                        navigation.selectedDay = Calendar.current.startOfDay(for: date)
                    }
                } else {
                    Theme.listBackground.ignoresSafeArea()
                }
            }
            .background(Theme.listBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .alert("New task", isPresented: $showComposer) {
                TextField("Task name", text: $composerText)
                Button("Add") {
                    let name = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        store?.create(name: name, parentID: composerParentID)
                    }
                    composerText = ""
                    composerParentID = ""
                }
                Button("Cancel", role: .cancel) {
                    composerText = ""
                    composerParentID = ""
                }
            } message: {
                Text(composerParentID.isEmpty ? "Added to the list." : "Nested under the selected task.")
            }
        }
        .onAppear {
            if store == nil {
                let next = TaskTreeStore(context: modelContext, uid: uid)
                next.seedGuestDataIfNeeded()
                store = next
                IntentStore.live = next
                EventIndex.scheduleSync(snapshots: next.allSnapshots)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store?.reload()
                if let store {
                    IntentStore.live = store
                    EventIndex.scheduleSync(snapshots: store.allSnapshots)
                }
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
                    .opacity(0.5)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
                    .offset(x: top.x - origin.minX, y: top.y - origin.minY)
            }
            .allowsHitTesting(false)
        }
    }

    private func selectedTaskBinding(_ store: TaskTreeStore) -> Binding<TaskIdentity?> {
        Binding(
            get: {
                guard let id = navigation.selectedTaskID else { return nil }
                return TaskIdentity(id: id)
            },
            set: { navigation.selectedTaskID = $0?.id }
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
        .frame(height: 36)
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
