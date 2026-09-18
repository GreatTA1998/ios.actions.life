import SwiftUI

struct TaskRowView: View {
    let tree: TaskTree
    let depth: Int
    @Bindable var store: TaskTreeStore
    @Binding var selectedTaskID: String?
    @Binding var composer: ComposerSlot?
    @Binding var composerText: String
    var onCommitComposer: () -> Void
    var onCancelComposer: () -> Void
    @Environment(HomeChrome.self) private var chrome

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if !tree.children.isEmpty {
                    Button {
                        store.setCollapsed(tree.id, isCollapsed: !tree.task.isCollapsed)
                    } label: {
                        Image(systemName: tree.task.isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 16)
                }

                Button {
                    store.toggleDone(tree.id)
                } label: {
                    Image(systemName: tree.task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(tree.task.isDone ? Theme.accent : Theme.secondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tree.task.isDone ? "Mark not done" : "Mark done")

                Button {
                    selectedTaskID = tree.id
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tree.task.name.isEmpty ? "Untitled" : tree.task.name)
                            .font(depth == 0 ? .body.weight(.medium) : .subheadline)
                            .strikethrough(tree.task.isDone)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        if !tree.task.startDateISO.isEmpty {
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(Rectangle())
            .background {
                if chrome.showsNestPreview(for: tree.id) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.dragPreview.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    Theme.dragPreview.opacity(0.6),
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                )
                        }
                }
            }
            .background { DropZoneReporter(kind: .nest(tree.id)) }
            .taskDragLift(id: tree.id, name: tree.task.name, duration: tree.task.duration) { target in
                store.applyDrop(target, taskID: tree.id, fromCalendar: false)
            }
            .allowsHitTesting(!chrome.isResizing)
            .contextMenu {
                Button("Open", systemImage: "doc.text") { selectedTaskID = tree.id }
                Button("Add subtask", systemImage: "plus") {
                    composerText = ""
                    composer = ComposerSlot(parentID: tree.id, index: tree.children.count)
                    store.setCollapsed(tree.id, isCollapsed: false)
                }
                Button("Schedule today", systemImage: "calendar") {
                    store.schedule(tree.id, dayISO: DateISO.dayString(from: .now), time: DateISO.timeString(from: .now))
                }
                Button("Indent", systemImage: "increase.indent") { store.indent(tree.id) }
                Button("Outdent", systemImage: "decrease.indent") { store.outdent(tree.id) }
                Divider()
                Button("Archive from list", systemImage: "archivebox") { store.archive(tree.id) }
            }

            if !tree.task.isCollapsed {
                ForEach(Array(tree.children.enumerated()), id: \.element.id) { index, child in
                    composerOrDropzone(parentID: tree.id, index: index)
                    TaskRowView(
                        tree: child,
                        depth: depth + 1,
                        store: store,
                        selectedTaskID: $selectedTaskID,
                        composer: $composer,
                        composerText: $composerText,
                        onCommitComposer: onCommitComposer,
                        onCancelComposer: onCancelComposer
                    )
                }
                composerOrDropzone(parentID: tree.id, index: tree.children.count)
            }
        }
    }

    @ViewBuilder
    private func composerOrDropzone(parentID: String, index: Int) -> some View {
        if composer == ComposerSlot(parentID: parentID, index: index) {
            InlineTaskComposer(
                text: $composerText,
                font: .subheadline,
                onSubmit: onCommitComposer,
                onCancel: onCancelComposer
            )
            .padding(.leading, CGFloat(depth + 1) * 18)
        } else {
            ListDropzone(parentID: parentID, index: index, isRoot: false) {
                composerText = ""
                composer = ComposerSlot(parentID: parentID, index: index)
            }
            .padding(.leading, CGFloat(depth + 1) * 18)
        }
    }

    private var badge: String {
        if tree.task.startTime.isEmpty {
            return tree.task.startDateISO
        }
        return "\(tree.task.startDateISO) · \(tree.task.startTime)"
    }
}
