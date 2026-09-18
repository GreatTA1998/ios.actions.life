import SwiftUI

struct InboxView: View {
    @Bindable var store: TaskTreeStore
    @Binding var selectedTaskID: String?
    var onAddRoot: () -> Void
    var onAddChild: (String) -> Void
    @Environment(HomeChrome.self) private var chrome

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(action: onAddRoot) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityLabel("Add task")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 2)

            if store.inbox.isEmpty {
                ContentUnavailableView {
                    Label("Nothing on the list", systemImage: "checklist")
                } description: {
                    Text("Add a task, then open it to nest subtasks or put it on a day.")
                } actions: {
                    Button("Add task", action: onAddRoot)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.inbox) { tree in
                            TaskRowView(
                                tree: tree,
                                depth: 0,
                                store: store,
                                selectedTaskID: $selectedTaskID,
                                onAddChild: onAddChild
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 28)
                }
                .scrollDisabled(chrome.pointerCaptured)
            }
        }
        .background(Theme.listBackground)
        .overlay {
            if chrome.showsListPreview() {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.dragPreview.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .background { DropZoneReporter(kind: .list) }
    }
}
