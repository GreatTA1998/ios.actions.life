import SwiftUI

struct InboxView: View {
    @Bindable var store: TaskTreeStore
    @Binding var selectedTaskID: String?
    @Binding var composer: ComposerSlot?
    @Binding var composerText: String
    var onCommitComposer: () -> Void
    var onCancelComposer: () -> Void
    @Environment(HomeChrome.self) private var chrome

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(store.inbox.enumerated()), id: \.element.id) { index, tree in
                    composerOrDropzone(parentID: "", index: index, isRoot: true)
                    TaskRowView(
                        tree: tree,
                        depth: 0,
                        store: store,
                        selectedTaskID: $selectedTaskID,
                        composer: $composer,
                        composerText: $composerText,
                        onCommitComposer: onCommitComposer,
                        onCancelComposer: onCancelComposer
                    )
                }
                composerOrDropzone(
                    parentID: "",
                    index: store.inbox.count,
                    isRoot: true,
                    fillRemaining: true
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollDisabled(chrome.isResizing)
        .overlay {
            ScrollEdgeBridge(chrome: chrome, pane: .list)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .center) {
            if store.inbox.isEmpty, composer == nil {
                Text("Tap a gap to add a task")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                    .allowsHitTesting(false)
            }
        }
        .background(Theme.listBackground)
        .background { DropZoneReporter(kind: .list) }
    }

    @ViewBuilder
    private func composerOrDropzone(
        parentID: String,
        index: Int,
        isRoot: Bool,
        fillRemaining: Bool = false
    ) -> some View {
        if composer == ComposerSlot(parentID: parentID, index: index) {
            InlineTaskComposer(
                text: $composerText,
                font: isRoot ? .body.weight(.medium) : .subheadline,
                onSubmit: onCommitComposer,
                onCancel: onCancelComposer
            )
            .padding(.leading, isRoot ? 0 : 18)
        } else {
            ListDropzone(
                parentID: parentID,
                index: index,
                isRoot: isRoot,
                fillRemaining: fillRemaining
            ) {
                composerText = ""
                composer = ComposerSlot(parentID: parentID, index: index)
            }
        }
    }
}
