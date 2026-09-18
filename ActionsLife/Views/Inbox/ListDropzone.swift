import SwiftUI

struct ComposerSlot: Equatable {
    var parentID: String
    var index: Int
}

/// Web `Dropzone.svelte` / Expo `Dropzone.tsx`: tappable gap between tasks.
/// Root 24px / sub 16px; trailing ghost zones overhang the next row like web `ghost-negative`.
struct ListDropzone: View {
    let parentID: String
    let index: Int
    var isRoot: Bool = true
    /// Trailing empty area under the list — expands so tapping “empty space” creates a root task.
    var fillRemaining: Bool = false
    /// Web/Expo trailing subtask zone: overlaps the following row so the gap stays easy to hit.
    var ghost: Bool = false
    var onTap: () -> Void

    @Environment(HomeChrome.self) private var chrome

    private var layoutHeight: CGFloat {
        if fillRemaining { return 120 }
        // Match web HEIGHTS.ROOT_DROPZONE / SUB_DROPZONE (1.5rem / 1rem).
        return isRoot ? 24 : 16
    }

    var body: some View {
        ZStack {
            // Non-clear fill so ScrollView reliably delivers taps (Color.clear often drops hits).
            Color.primary.opacity(0.001)
            if chrome.showsSlotPreview(parentID: parentID, index: index) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.dragPreview.opacity(0.15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                Theme.dragPreview.opacity(0.6),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    }
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: layoutHeight)
        .contentShape(Rectangle())
        // Expo native hit target is slightly taller than the visual gap; expand without shifting layout.
        .padding(.vertical, isRoot || fillRemaining ? 2 : 3)
        .contentShape(Rectangle())
        .padding(.vertical, isRoot || fillRemaining ? -2 : -3)
        .offset(y: ghost ? -layoutHeight : 0)
        .zIndex(ghost ? 3 : 0)
        .highPriorityGesture(
            TapGesture().onEnded {
                guard chrome.drag == nil, !chrome.isResizing else { return }
                onTap()
            }
        )
        .background { DropZoneReporter(kind: .listSlot(parentID: parentID, index: index)) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRoot ? "Add task" : "Add subtask")
        .accessibilityHint("Opens a new task field here")
        .accessibilityAction { onTap() }
    }
}

struct InlineTaskComposer: View {
    @Binding var text: String
    var font: Font = .body
    var onSubmit: () -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(Theme.secondaryInk)
            TextField("Task name", text: $text)
                .font(font)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(onSubmit)
            Button("Cancel", action: onCancel)
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.dragPreview.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .onAppear { focused = true }
    }
}
