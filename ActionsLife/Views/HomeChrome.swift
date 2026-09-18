import SwiftUI

/// Shared pointer-session flags so the split handle, scroll views, and drop
/// targets cannot all handle the same drag at once.
@Observable
final class HomeChrome {
    var isResizing = false
    var dropTargetedCount = 0

    var isDropTargeted: Bool { dropTargetedCount > 0 }

    func setDropTargeted(_ hovering: Bool) {
        if hovering {
            dropTargetedCount += 1
        } else {
            dropTargetedCount = max(0, dropTargetedCount - 1)
        }
    }
}
