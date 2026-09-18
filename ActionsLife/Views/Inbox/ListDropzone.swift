import SwiftUI

struct ComposerSlot: Equatable {
    var parentID: String
    var index: Int
}

struct ListDropzone: View {
    let parentID: String
    let index: Int
    var isRoot: Bool = true
    var fillRemaining: Bool = false
    var onTap: () -> Void

    @Environment(HomeChrome.self) private var chrome

    var body: some View {
        let height: CGFloat = isRoot ? 22 : 14
        ZStack {
            Color.clear
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
        .frame(minHeight: height)
        .frame(maxHeight: fillRemaining ? .infinity : nil)
        .contentShape(Rectangle())
        .background { DropZoneReporter(kind: .listSlot(parentID: parentID, index: index)) }
        .onTapGesture {
            guard chrome.drag == nil, !chrome.isResizing else { return }
            onTap()
        }
        .accessibilityLabel(isRoot ? "Add task" : "Add subtask")
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
