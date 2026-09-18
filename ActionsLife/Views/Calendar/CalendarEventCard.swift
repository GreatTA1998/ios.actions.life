import SwiftUI

struct CalendarEventCard: View {
    let task: TaskSnapshot
    var children: [TaskSnapshot] = []
    var compact: Bool = false
    var onToggle: () -> Void
    var onOpen: () -> Void
    var onToggleChild: (String) -> Void = { _ in }
    var onDrop: (HomeChrome.DropTarget) -> Void
    var onResizeDuration: (Double) -> Void = { _ in }
    /// Timed canvas draws the capsule in layout so empty hours stay tappable.
    var showsDurationHandle: Bool = true
    @Environment(HomeChrome.self) private var chrome

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 4) {
            HStack(alignment: .center, spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(compact ? .body : .title3)
                        .foregroundStyle(task.isDone ? Theme.accent : Theme.ink.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

                Text(task.name.isEmpty ? "Untitled" : task.name)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(compact ? 1 : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard chrome.durationResize == nil, chrome.drag == nil else { return }
                        onOpen()
                    }

                if !children.isEmpty {
                    Text("\(children.filter(\.isDone).count)/\(children.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }

            if !compact, !task.notes.isEmpty {
                Text(task.notes)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(4)
            }

            if !compact {
                ForEach(children.prefix(6)) { child in
                    Button {
                        onToggleChild(child.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: child.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline)
                                .foregroundStyle(child.isDone ? Theme.accent : Theme.ink.opacity(0.45))
                            Text(child.name.isEmpty ? "Untitled" : child.name)
                                .font(.subheadline)
                                .strikethrough(child.isDone)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 22)
                    .accessibilityLabel(child.isDone ? "Mark \(child.name) not done" : "Mark \(child.name) done")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        }
        .opacity(task.isDone ? 0.55 : 1)
        .overlay {
            if chrome.showsNestPreview(for: task.id) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        Theme.dragPreview.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
        }
        .background { DropZoneReporter(kind: .nest(task.id)) }
        .taskDragLift(id: task.id, name: task.name, duration: task.duration, fromCalendar: true, onDrop: onDrop)
        .overlay(alignment: .bottom) {
            if !compact, showsDurationHandle {
                DurationEdgeHandle(task: task, onResize: onResizeDuration)
            }
        }
    }
}

/// 28pt duration edge. Timed canvas places this in layout at the capsule so
/// UIKit can hit it; empty hours still reach hour-grid SpatialTap.
struct DurationEdgeHandle: View {
    let task: TaskSnapshot
    var onResize: (Double) -> Void
    @Environment(HomeChrome.self) private var chrome
    @State private var swiftUIDrag = false
    @State private var startY: CGFloat = 0

    var body: some View {
        Color.primary.opacity(0.001)
            .frame(maxWidth: .infinity)
            .frame(height: HomeChrome.durationHandleHit)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    if chrome.durationResize?.taskID == task.id {
                        Rectangle()
                            .fill(Theme.dragPreview.opacity(0.85))
                            .frame(height: 1)
                    }
                    Capsule()
                        .fill(Theme.handle)
                        .frame(width: 22, height: 3)
                        .padding(.bottom, 4)
                }
                .allowsHitTesting(false)
            }
            .overlay {
                DurationResizeBridge(
                    enabled: chrome.drag == nil && !chrome.isResizing
                        && (chrome.durationResize == nil || chrome.durationResize?.taskID == task.id),
                    onBegan: beginIfNeeded,
                    onChanged: { chrome.moveDurationResize(deltaY: $0) },
                    onEnded: finishIfNeeded,
                    onCancel: {
                        swiftUIDrag = false
                        chrome.cancelDurationResize()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .highPriorityGesture(drag)
            .accessibilityLabel("Resize duration")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard chrome.drag == nil, !chrome.isResizing else { return }
                if !swiftUIDrag {
                    swiftUIDrag = true
                    startY = value.startLocation.y
                    beginIfNeeded()
                }
                chrome.moveDurationResize(deltaY: value.location.y - startY)
            }
            .onEnded { _ in
                finishIfNeeded()
            }
    }

    private func beginIfNeeded() {
        if chrome.durationResize?.taskID != task.id {
            chrome.beginDurationResize(taskID: task.id, duration: task.duration)
        }
    }

    private func finishIfNeeded() {
        swiftUIDrag = false
        if let result = chrome.finishDurationResize() {
            onResize(result.duration)
        }
    }
}
