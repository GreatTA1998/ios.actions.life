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
    @State private var showComposer = false
    @State private var showMenu = false
    @State private var composerParentID = ""
    @State private var dragStartSplit: Double?
    @State private var chrome = HomeChrome()

    var body: some View {
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
                                selectedDay: $selectedDay,
                                selectedTaskID: $selectedTaskID,
                                columnWidth: columnWidth,
                                onJumpToday: {
                                    selectedDay = Calendar.current.startOfDay(for: .now)
                                },
                                onMenu: { showMenu = true }
                            )
                            .frame(height: calendarHeight)

                            SplitHandle(
                                enabled: !chrome.isDropTargeted,
                                onChanged: { translation in
                                    let start = dragStartSplit ?? store.listHeightSplit
                                    if dragStartSplit == nil {
                                        dragStartSplit = start
                                        chrome.isResizing = true
                                    }
                                    store.setListHeightSplitLive(start - translation / geo.size.height)
                                },
                                onEnded: {
                                    dragStartSplit = nil
                                    chrome.isResizing = false
                                    store.setListHeightSplit(store.listHeightSplit)
                                }
                            )

                            InboxView(
                                store: store,
                                selectedTaskID: $selectedTaskID,
                                onAddRoot: { showComposer = true; composerParentID = "" },
                                onAddChild: { parent in
                                    composerParentID = parent
                                    showComposer = true
                                }
                            )
                            .frame(maxHeight: .infinity)
                            .scrollDisabled(chrome.isResizing)
                            .allowsHitTesting(!chrome.isResizing)
                        }
                    }
                    .environment(chrome)
                    .sheet(item: selectedTaskBinding(store)) { record in
                        TaskDetailSheet(store: store, taskID: record.id)
                    }
                    .confirmationDialog("actions.life", isPresented: $showMenu, titleVisibility: .visible) {
                        Button("Add task") {
                            composerParentID = ""
                            showComposer = true
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
            }
        }
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
    var enabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

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
        .highPriorityGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    onChanged(value.translation.height)
                }
                .onEnded { _ in
                    onEnded()
                }
        )
        .allowsHitTesting(enabled)
        .accessibilityLabel("Resize list")
    }

    private var capsule: some View {
        Capsule()
            .fill(Theme.handle)
            .frame(width: 22, height: 1.5)
    }
}
