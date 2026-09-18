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
            if !compact {
                DurationEdgeHandle(
                    task: task,
                    onResize: onResizeDuration
                )
                .frame(maxWidth: .infinity)
                .frame(height: HomeChrome.durationCapsuleHit)
            }
        }
    }
}

/// 16pt painted capsule. SwiftUI `DragGesture` never fired inside the hour
/// `ScrollView` (`c7a355e` simultaneous, `b45eccd` highPriority) — UIKit's
/// scroll pan is exclusive. This view **is** the hit target: a UIView pan on
/// the capsule, and the hour scroller's pan must fail it. Title taps still
/// open Details. Pin `contentOffset` only after `.began`. Never
/// `isScrollEnabled = false` on touch-down.
struct DurationEdgeHandle: View {
    let task: TaskSnapshot
    var onResize: (Double) -> Void
    @Environment(HomeChrome.self) private var chrome

    var body: some View {
        DurationHandleBridge(
            enabled: chrome.drag == nil && !chrome.isResizing
                && (chrome.durationResize == nil || chrome.durationResize?.taskID == task.id),
            onBegan: beginIfNeeded,
            onChanged: { chrome.moveDurationResize(deltaY: $0) },
            onEnded: finishIfNeeded,
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

    private func finishIfNeeded() {
        if let result = chrome.finishDurationResize() {
            onResize(result.duration)
        }
    }
}
