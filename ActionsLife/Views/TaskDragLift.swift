import SwiftUI
import UIKit

/// Hold 150ms (web/Expo) then drag in window coordinates.
///
/// The recognizer is installed on the enclosing `UIScrollView` (an ancestor of
/// both this `.background` wrapper **and** the SwiftUI row buttons). Installing
/// on the background host never sees the touch — a still hold never lifts a
/// ghost, and movement becomes a list scroll.
///
/// Do **not** add `shouldBeRequiredToFailBy` → scroll pan. That relationship
/// leaks across SwiftUI rebuilds after a split resize and freezes both panes.
/// Exclusive-vs-pan is enough: a flick fails this recognizer via slop, a still
/// hold begins and the pan cannot share the touch. `pointerCaptured` then
/// disables scroll for edge autoscroll + calendar drop.
struct TaskDragLift: ViewModifier {
    let taskID: String
    let name: String
    let duration: Double
    var fromCalendar: Bool = false
    var onDrop: (HomeChrome.DropTarget) -> Void

    @Environment(HomeChrome.self) private var chrome
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { frame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, newValue in
                            frame = newValue
                        }
                }
            }
            .background {
                HoldThenDragBridge(
                    enabled: !chrome.isResizing && (chrome.drag == nil || chrome.drag?.taskID == taskID),
                    holdDelay: HomeChrome.holdDelay,
                    slop: HomeChrome.touchSlop,
                    rowFrame: frame,
                    isActive: chrome.drag?.taskID == taskID,
                    onHold: { point, rowFrame in
                        chrome.beginDrag(
                            taskID: taskID,
                            name: name,
                            duration: duration,
                            finger: point,
                            frame: rowFrame.width > 1 ? rowFrame : frame,
                            fromCalendar: fromCalendar
                        )
                    },
                    onMove: { point in
                        guard chrome.drag?.taskID == taskID else { return }
                        chrome.moveDrag(finger: point)
                    },
                    onEnd: {
                        guard chrome.drag?.taskID == taskID else {
                            chrome.cancelDrag()
                            return
                        }
                        onDrop(chrome.finishDrag())
                    },
                    onCancel: {
                        if chrome.drag?.taskID == taskID || chrome.isLifting {
                            chrome.cancelDrag()
                        }
                    }
                )
            }
            .opacity(chrome.drag?.taskID == taskID ? 0.35 : 1)
    }
}

extension View {
    func taskDragLift(
        id: String,
        name: String,
        duration: Double,
        fromCalendar: Bool = false,
        onDrop: @escaping (HomeChrome.DropTarget) -> Void
    ) -> some View {
        modifier(TaskDragLift(taskID: id, name: name, duration: duration, fromCalendar: fromCalendar, onDrop: onDrop))
    }
}

struct DropZoneReporter: View {
    let kind: HomeChrome.DropZone.Kind

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: DropZonePreferenceKey.self,
                value: [HomeChrome.DropZone(kind: kind, frame: geo.frame(in: .global))]
            )
        }
    }
}

struct DropZonePreferenceKey: PreferenceKey {
    static var defaultValue: [HomeChrome.DropZone] = []
    static func reduce(value: inout [HomeChrome.DropZone], nextValue: () -> [HomeChrome.DropZone]) {
        value.append(contentsOf: nextValue())
    }
}

struct PaneFrameReporter: View {
    enum Pane { case calendar, list, home }
    let pane: Pane
    var onChange: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.frame(in: .global)) }
                .onChange(of: geo.frame(in: .global)) { _, frame in onChange(frame) }
        }
    }
}

/// Drives pane autoscroll from a CADisplayLink while a row is lifted.
///
/// Must live as an **overlay on the pane** (not a `.background` inside the
/// ScrollView). SwiftUI representables inside scroll content are often siblings
/// of `UIScrollView`, so ancestor search finds nothing and the list never moves.
/// A display link + `layoutSubviews` re-apply also beats SwiftUI resetting
/// `contentOffset` when `scrollDisabled` / chrome ticks rebuild the tree.
struct ScrollEdgeBridge: UIViewRepresentable {
    var chrome: HomeChrome
    var pane: EdgeScrollPane

    enum EdgeScrollPane {
        case list
        case calendar
    }

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.chrome = chrome
        view.pane = pane
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        uiView.chrome = chrome
        uiView.pane = pane
        uiView.syncDisplayLink()
    }

    static func dismantleUIView(_ uiView: BridgeView, coordinator: Void) {
        uiView.stopDisplayLink()
    }

    final class BridgeView: UIView {
        var chrome: HomeChrome?
        var pane: EdgeScrollPane = .list
        private var displayLink: CADisplayLink?
        private weak var scroll: UIScrollView?
        private var stickyOffset: CGPoint?

        deinit { displayLink?.invalidate() }

        func syncDisplayLink() {
            if window != nil, chrome?.drag != nil {
                startDisplayLink()
            } else if chrome?.drag == nil {
                stopDisplayLink()
            }
        }

        func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
            stickyOffset = nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            syncDisplayLink()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let stickyOffset, chrome?.drag != nil, let scroll = resolveScrollView() {
                if scroll.contentOffset != stickyOffset {
                    apply(offset: stickyOffset, on: scroll)
                }
            }
        }

        private func startDisplayLink() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc func tick() {
            guard let chrome, chrome.drag != nil, let finger = chrome.drag?.finger else {
                stickyOffset = nil
                return
            }
            let viewport = pane == .list ? chrome.listPane : chrome.calendarPane
            let axes: DropMath.AxisSet = pane == .list ? [.vertical] : [.horizontal, .vertical]
            let delta = DropMath.edgeScrollDelta(
                finger: finger,
                viewport: viewport,
                band: HomeChrome.edgeBand,
                step: HomeChrome.edgeStep,
                axes: axes,
                ghostTop: chrome.ghostTop,
                ghostSize: chrome.drag?.ghostSize ?? .zero
            )
            guard let scroll = resolveScrollView() else { return }
            if delta == .zero {
                stickyOffset = scroll.contentOffset
                return
            }
            let next = clampedOffset(scroll.contentOffset, adding: delta, on: scroll)
            apply(offset: next, on: scroll)
            stickyOffset = next
        }

        private func clampedOffset(_ current: CGPoint, adding delta: CGSize, on scroll: UIScrollView) -> CGPoint {
            let inset = scroll.adjustedContentInset
            let contentH = max(scroll.contentSize.height, contentExtent(of: scroll, axis: .vertical))
            let contentW = max(scroll.contentSize.width, contentExtent(of: scroll, axis: .horizontal))
            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(minX, contentW - scroll.bounds.width + inset.right)
            let maxY = max(minY, contentH - scroll.bounds.height + inset.bottom)
            return CGPoint(
                x: min(maxX, max(minX, current.x + delta.width)),
                y: min(maxY, max(minY, current.y + delta.height))
            )
        }

        private func contentExtent(of scroll: UIScrollView, axis: DropMath.AxisSet) -> CGFloat {
            scroll.subviews.reduce(0) { best, sub in
                if axis.contains(.vertical) { return max(best, sub.frame.maxY) }
                return max(best, sub.frame.maxX)
            }
        }

        private func apply(offset: CGPoint, on scroll: UIScrollView) {
            scroll.isScrollEnabled = true
            scroll.setContentOffset(offset, animated: false)
        }

        /// Search this pane's subtree only — match the pane's global frame so
        /// we never climb into the home VStack and steal the other scroller.
        private func resolveScrollView() -> UIScrollView? {
            let paneRect = pane == .list ? chrome?.listPane : chrome?.calendarPane
            var view: UIView? = self
            var fallback: UIView = self
            while let current = view {
                if current is UIWindow { break }
                fallback = current
                let frame = current.convert(current.bounds, to: nil)
                if let paneRect, !paneRect.isNull, !paneRect.isEmpty,
                   current.bounds.height > 60,
                   frame.intersection(paneRect).height > paneRect.height * 0.5
                {
                    if let found = bestScrollView(in: current) {
                        scroll = found
                        return found
                    }
                }
                view = current.superview
            }
            if let found = bestScrollView(in: fallback) {
                scroll = found
                return found
            }
            return scroll
        }

        private func bestScrollView(in root: UIView) -> UIScrollView? {
            var best: UIScrollView?
            var bestSlack: CGFloat = -1
            func walk(_ node: UIView) {
                if let scroll = node as? UIScrollView {
                    let extraY = max(scroll.contentSize.height, contentExtent(of: scroll, axis: .vertical)) - scroll.bounds.height
                    let extraX = max(scroll.contentSize.width, contentExtent(of: scroll, axis: .horizontal)) - scroll.bounds.width
                    // List: skip the calendar (wide 2-axis) scroller if we climbed too far.
                    if pane == .list, extraX > extraY + 80, extraX > 80 {
                        // still walk children
                    } else {
                        let slack = pane == .list ? extraY : max(extraX, extraY)
                        let score = slack + scroll.bounds.height * 0.001
                        if score > bestSlack {
                            bestSlack = score
                            best = scroll
                        }
                    }
                }
                for sub in node.subviews { walk(sub) }
            }
            walk(root)
            return best
        }
    }
}

/// UIKit split-handle pan. Mirrors Expo SplitPane: always clear dragging on
/// release **and** terminate — SwiftUI DragGesture often skips `onEnded` when
/// the VStack rebuilds mid-drag, which used to leave `isResizing` stuck and
/// freeze both panes (`allowsHitTesting(false)` + `scrollDisabled`).
struct SplitResizeBridge: UIViewRepresentable {
    var enabled: Bool
    var onBegan: () -> Void
    var onChanged: (_ translationY: CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> HandleView {
        let view = HandleView()
        view.coordinator = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: HandleView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pan.isEnabled = enabled
        uiView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SplitResizeBridge
        let pan = UIPanGestureRecognizer()

        init(parent: SplitResizeBridge) {
            self.parent = parent
            super.init()
            pan.addTarget(self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = true
            pan.maximumNumberOfTouches = 1
        }

        func attach(to view: UIView) {
            guard pan.view !== view else { return }
            pan.view?.removeGestureRecognizer(pan)
            view.addGestureRecognizer(pan)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.onBegan()
                parent.onChanged(gesture.translation(in: gesture.view).y)
            case .changed:
                parent.onChanged(gesture.translation(in: gesture.view).y)
            case .ended, .cancelled, .failed:
                // Always clear — same contract as Expo onPanResponderTerminate.
                parent.onEnded()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            parent.enabled
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }

    final class HandleView: UIView {
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }
    }
}

/// Pure rules for the UIKit hold-to-drag recognizer. Kept here so tests can lock
/// the 150ms lift contract without a Simulator.
enum HoldThenDragPolicy {
    static func shouldReceive(enabled: Bool, finger: CGPoint, rowFrame: CGRect) -> Bool {
        guard enabled, rowFrame.width > 1, rowFrame.height > 1 else { return false }
        return rowFrame.insetBy(dx: -2, dy: -2).contains(finger)
    }

    /// Never share with a pan. A flick fails this recognizer via slop so the
    /// scroll pan can begin; a still hold begins and the pan is cancelled.
    /// Do not add `shouldBeRequiredToFailBy` — that leaks after split resize.
    static func shouldRecognizeSimultaneously(otherIsPan: Bool, isDragging: Bool) -> Bool {
        if otherIsPan { return false }
        return !isDragging
    }

    /// UIViewRepresentable backgrounds can lay out at 0×0 for a frame; do not
    /// let that reject a press on the real SwiftUI row.
    static func preferredRowFrame(uiKit: CGRect, swiftUI: CGRect) -> CGRect {
        let uiArea = max(0, uiKit.width) * max(0, uiKit.height)
        let swiftArea = max(0, swiftUI.width) * max(0, swiftUI.height)
        if uiArea >= swiftArea, uiKit.width > 1, uiKit.height > 1 {
            return uiKit
        }
        return swiftUI
    }
}

/// Long-press that lifts a drag ghost after `holdDelay`, then tracks in window space.
struct HoldThenDragBridge: UIViewRepresentable {
    var enabled: Bool
    var holdDelay: TimeInterval
    var slop: CGFloat
    var rowFrame: CGRect
    var isActive: Bool
    var onHold: (CGPoint, CGRect) -> Void
    var onMove: (CGPoint) -> Void
    var onEnd: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        context.coordinator.installer = view
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.installer = uiView
        uiView.coordinator = context.coordinator
        context.coordinator.press?.isEnabled = enabled
        context.coordinator.press?.minimumPressDuration = holdDelay
        context.coordinator.press?.allowableMovement = slop
        if isActive {
            context.coordinator.syncDragging(isActive: true)
        } else {
            context.coordinator.syncDragging(isActive: false)
        }
        uiView.ensureInstalled()
    }

    static func dismantleUIView(_ uiView: InstallerView, coordinator: Coordinator) {
        uiView.uninstall()
        coordinator.installer = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HoldThenDragBridge
        weak var press: UILongPressGestureRecognizer?
        weak var installer: InstallerView?
        private(set) var dragging = false

        init(parent: HoldThenDragBridge) {
            self.parent = parent
        }

        func syncDragging(isActive: Bool) {
            if isActive {
                dragging = true
            } else if press?.state != .began && press?.state != .changed {
                dragging = false
            }
        }

        @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: nil)
            switch gesture.state {
            case .began:
                dragging = true
                haltEnclosingScroll()
                parent.onHold(point, resolvedRowFrame())
            case .changed:
                guard dragging else { return }
                parent.onMove(point)
            case .ended:
                guard dragging else { return }
                dragging = false
                parent.onEnd()
            case .cancelled, .failed:
                if dragging {
                    dragging = false
                    parent.onCancel()
                }
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            HoldThenDragPolicy.shouldReceive(
                enabled: parent.enabled,
                finger: touch.location(in: nil),
                rowFrame: resolvedRowFrame()
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            HoldThenDragPolicy.shouldRecognizeSimultaneously(
                otherIsPan: other is UIPanGestureRecognizer,
                isDragging: dragging
            )
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            HoldThenDragPolicy.shouldReceive(
                enabled: parent.enabled,
                finger: gestureRecognizer.location(in: nil),
                rowFrame: resolvedRowFrame()
            )
        }

        func resolvedRowFrame() -> CGRect {
            var uiKit = CGRect.zero
            if let installer, installer.window != nil {
                uiKit = installer.convert(installer.bounds, to: nil)
            }
            return HoldThenDragPolicy.preferredRowFrame(uiKit: uiKit, swiftUI: parent.rowFrame)
        }

        /// Stop an in-flight pan so a just-lifted ghost is not also a list scroll.
        private func haltEnclosingScroll() {
            var view: UIView? = installer
            while let current = view {
                if let scroll = current as? UIScrollView {
                    scroll.setContentOffset(scroll.contentOffset, animated: false)
                    let pan = scroll.panGestureRecognizer
                    if pan.state == .began || pan.state == .changed {
                        pan.isEnabled = false
                        pan.isEnabled = true
                    }
                    return
                }
                view = current.superview
            }
        }
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?
        private weak var installedOn: UIView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            ensureInstalled()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            ensureInstalled()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            ensureInstalled()
        }

        func ensureInstalled() {
            guard let coordinator else { return }
            guard window != nil || superview != nil else {
                uninstall()
                return
            }
            let host = findHost()
            // Never rip out a recognizer that already lifted — SwiftUI
            // `scrollDisabled` rebuilds must not cancel an in-flight drag.
            if coordinator.dragging, coordinator.press != nil { return }
            if installedOn === host, coordinator.press != nil { return }
            uninstall()
            guard let host else { return }
            let press = UILongPressGestureRecognizer(
                target: coordinator,
                action: #selector(Coordinator.handlePress(_:))
            )
            press.minimumPressDuration = coordinator.parent.holdDelay
            press.allowableMovement = coordinator.parent.slop
            // Cancel the row tap / context-menu press once we lift so a 150ms
            // hold shows the ghost instead of opening the task or a menu.
            press.cancelsTouchesInView = true
            press.delegate = coordinator
            host.addGestureRecognizer(press)
            coordinator.press = press
            installedOn = host
            isUserInteractionEnabled = false
        }

        func uninstall() {
            if let press = coordinator?.press {
                press.view?.removeGestureRecognizer(press)
            }
            coordinator?.press = nil
            installedOn = nil
        }

        /// Install on the enclosing UIScrollView (ancestor of both the SwiftUI
        /// buttons and this background wrapper) so the press sees the same
        /// touches as a row tap / XCUITest press. The `.background` host is a
        /// sibling of those buttons and never receives them.
        func findHost() -> UIView? {
            var view: UIView? = superview
            while let current = view {
                if current is UIScrollView { return current }
                view = current.superview
            }
            // Never fall back to the `.background` host — that sibling view
            // does not receive row-button touches, so a still hold never lifts.
            return window
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            nil
        }
    }
}
