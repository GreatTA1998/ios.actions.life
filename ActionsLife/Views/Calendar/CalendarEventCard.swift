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
    @Environment(HomeChrome.self) private var chrome

    var body: some View {
        Group {
            if compact {
                cardBody
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                timedLayout
            }
        }
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
    }

    /// Body UIControl fills the slot above the 16pt capsule (not a 0×0
    /// ZStack sibling). Painted title overlays it; taps hit the control.
    private var timedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardBodyTapBridge {
                guard chrome.durationResize == nil, chrome.drag == nil else { return }
                onOpen()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                cardBody
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }

            DurationEdgeHandle(
                task: task,
                onResize: onResizeDuration
            )
            .frame(maxWidth: .infinity)
            .frame(height: HomeChrome.durationCapsuleHit)
        }
    }

    private var cardBody: some View {
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
    }
}

/// 16pt layout slot at the bottom of the timed card. `UIControl` tracking
/// commits window finger-Y into `setDuration` (`touchesMoved` never ran).
struct DurationEdgeHandle: View {
    let task: TaskSnapshot
    var onResize: (Double) -> Void
    @Environment(HomeChrome.self) private var chrome

    var body: some View {
        DurationHandleBridge(
            enabled: chrome.drag == nil && !chrome.isResizing
                && (chrome.durationResize == nil || chrome.durationResize?.taskID == task.id),
            startDuration: task.duration,
            pixelsPerHour: chrome.pixelsPerHour,
            snap: chrome.snapInterval,
            onBegan: beginIfNeeded,
            onChanged: { chrome.moveDurationResize(deltaY: $0) },
            onCommit: { minutes in
                chrome.cancelDurationResize()
                onResize(minutes)
            },
            onCancel: { chrome.cancelDurationResize() }
        )
        .frame(maxWidth: .infinity)
        .frame(height: HomeChrome.durationCapsuleHit)
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
        .background {
            ScrollOffsetLockBridge(locked: chrome.durationResize?.taskID == task.id)
        }
        .accessibilityLabel("Resize duration")
    }

    private func beginIfNeeded() {
        if chrome.durationResize?.taskID != task.id {
            chrome.beginDurationResize(taskID: task.id, duration: task.duration)
        }
    }
}
