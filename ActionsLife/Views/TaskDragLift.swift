import SwiftUI
import UIKit

/// Hold 150ms (web/Expo) then drag in window coordinates.
///
/// Important: do **not** require UIScrollView pans to fail before this recognizer.
/// That pattern (shouldBeRequiredToFailBy → pan) permanently breaks scrolling once
/// SwiftUI rebuilds the hierarchy after a split resize. Instead we coexist with
/// scroll until the hold fires, then HomeChrome.pointerCaptured disables scroll.
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
                    enabled: !chrome.isResizing
                        && chrome.durationResize == nil
                        && (chrome.drag == nil || chrome.drag?.taskID == taskID),
                    holdDelay: HomeChrome.holdDelay,
                    slop: HomeChrome.touchSlop,
                    isActive: chrome.drag?.taskID == taskID,
                    onHold: { point in
                        chrome.beginDrag(
                            taskID: taskID,
                            name: name,
                            duration: duration,
                            finger: point,
                            frame: frame,
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

/// Applies `delta` to the pane's UIScrollView. Background bridges sit beside the
/// ScrollView, so we search sibling subtrees — not only ancestors.
struct ScrollEdgeBridge: UIViewRepresentable {
    var delta: CGSize
    var generation: Int

    func makeUIView(context: Context) -> BridgeView {
        BridgeView()
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        guard delta != .zero else { return }
        uiView.apply(delta: delta)
    }

    final class BridgeView: UIView {
        func apply(delta: CGSize) {
            guard let scroll = findPaneScrollView() else { return }
            let maxX = max(0, scroll.contentSize.width - scroll.bounds.width)
            let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
            let next = CGPoint(
                x: min(maxX, max(0, scroll.contentOffset.x + delta.width)),
                y: min(maxY, max(0, scroll.contentOffset.y + delta.height))
            )
            guard next != scroll.contentOffset else { return }
            scroll.setContentOffset(next, animated: false)
        }

        private func findPaneScrollView() -> UIScrollView? {
            var child: UIView = self
            var parent = superview
            while let container = parent {
                if let scroll = container as? UIScrollView { return scroll }
                for sub in container.subviews where sub !== child {
                    if let found = firstScrollView(in: sub) { return found }
                }
                child = container
                parent = container.superview
            }
            return nil
        }

        private func firstScrollView(in root: UIView) -> UIScrollView? {
            if let scroll = root as? UIScrollView { return scroll }
            for sub in root.subviews {
                if let found = firstScrollView(in: sub) { return found }
            }
            return nil
        }
    }
}

/// Jumps the **hour** UIScrollView to `now − 48pt` (web `jumpToToday` y).
///
/// Y only, and only the nearest vertical ancestor. `b956880` wrote
/// `todayIndex × columnWidth` onto a 2-axis (or parent) scroller and shoved
/// Today/hours/list to x≈3070.
struct ScrollToYBridge: UIViewRepresentable {
    var y: CGFloat
    var generation: Int

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        uiView.targetY = y
        uiView.apply(generation: generation)
    }

    final class BridgeView: UIView {
        var targetY: CGFloat = 0
        private var startedGeneration = -1
        private var token = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil, startedGeneration == -1 {
                apply(generation: 0)
            }
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            if startedGeneration == -1 {
                apply(generation: 0)
            }
        }

        func apply(generation: Int) {
            guard generation != startedGeneration else { return }
            startedGeneration = generation
            token += 1
            attempt(token: token, remaining: 24)
        }

        private func attempt(token: Int, remaining: Int) {
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.token else { return }
                if let scroll = self.nearestVerticalScrollView() {
                    self.applyY(to: scroll)
                }
                if remaining > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                        self?.attempt(token: token, remaining: remaining - 1)
                    }
                }
            }
        }

        private func applyY(to scroll: UIScrollView) {
            let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
            let nextY = min(maxY, max(0, targetY))
            guard abs(scroll.contentOffset.y - nextY) > 0.5 else { return }
            scroll.setContentOffset(
                CGPoint(x: scroll.contentOffset.x, y: nextY),
                animated: false
            )
        }

        /// First ancestor that actually scrolls vertically. Never write X.
        /// Never walk into a parent just because it is also a UIScrollView.
        private func nearestVerticalScrollView() -> UIScrollView? {
            var view: UIView? = superview
            while let current = view {
                if let scroll = current as? UIScrollView,
                   scroll.bounds.height > 0,
                   scroll.contentSize.height > scroll.bounds.height + 1,
                   scroll.contentSize.height > targetY + 20
                {
                    return scroll
                }
                view = current.superview
            }
            return nil
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

/// Long-press that coexists with scroll until the hold fires.
struct HoldThenDragBridge: UIViewRepresentable {
    var enabled: Bool
    var holdDelay: TimeInterval
    var slop: CGFloat
    var isActive: Bool
    var onHold: (CGPoint) -> Void
    var onMove: (CGPoint) -> Void
    var onEnd: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.press?.isEnabled = enabled
        context.coordinator.press?.minimumPressDuration = holdDelay
        context.coordinator.press?.allowableMovement = slop
        uiView.coordinator = context.coordinator
        uiView.ensureInstalled()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HoldThenDragBridge
        weak var press: UILongPressGestureRecognizer?
        private var dragging = false

        init(parent: HoldThenDragBridge) {
            self.parent = parent
        }

        @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: nil)
            switch gesture.state {
            case .began:
                dragging = true
                parent.onHold(point)
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
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Before lift: let the scroll pan run (quick flicks must not wait 150ms).
            // After lift: HomeChrome.scrollDisabled takes over; refuse sharing.
            if dragging { return false }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            parent.enabled
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view else { return true }
            let y = touch.location(in: view).y
            return y <= view.bounds.height - HomeChrome.durationHandleHit
        }
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?
        private weak var installedOn: UIView?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            ensureInstalled()
        }

        func ensureInstalled() {
            guard let coordinator, let host = superview else { return }
            if installedOn === host, coordinator.press != nil { return }
            if let old = coordinator.press {
                old.view?.removeGestureRecognizer(old)
            }
            let press = UILongPressGestureRecognizer(
                target: coordinator,
                action: #selector(Coordinator.handlePress(_:))
            )
            press.minimumPressDuration = coordinator.parent.holdDelay
            press.allowableMovement = coordinator.parent.slop
            press.cancelsTouchesInView = false
            press.delegate = coordinator
            host.addGestureRecognizer(press)
            coordinator.press = press
            installedOn = host
            isUserInteractionEnabled = false
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            nil
        }
    }
}

/// Immediate pan on the visible duration capsule (no long-press).
///
/// Installed on the hour `UIScrollView` (that view is under the finger).
/// `shouldReceive` uses the handle **UIView** window frame (not GeometryReader
/// global — that lagged at `cafff4f`) and content-space math without picking a
/// SwiftUI canvas subview (`e2fba41` missed the painted capsule). Do **not**
/// set `isScrollEnabled = false` (`a0da6ed` cancelled the pan). Pin
/// `contentOffset`, force `.began` after a short vertical move, and write
/// `translation.y` through `.ended`. Card-body taps still open Details.
struct DurationResizeBridge: UIViewRepresentable {
    var enabled: Bool
    var capsuleInContent: CGRect
    var onBegan: () -> Void
    var onChanged: (_ translationY: CGFloat) -> Void
    var onEnded: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        context.coordinator.handleView = view
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.handleView = uiView
        if !context.coordinator.dragging {
            context.coordinator.pan.isEnabled = enabled
        }
        uiView.coordinator = context.coordinator
        uiView.ensureInstalled()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DurationResizeBridge
        let pan = DurationPanRecognizer()
        private(set) var dragging = false
        private var lockedOffsets: [(UIScrollView, CGPoint)] = []
        weak var handleView: InstallerView?

        init(parent: DurationResizeBridge) {
            self.parent = parent
            super.init()
            pan.owner = self
            pan.addTarget(self, action: #selector(handlePan(_:)))
            pan.delegate = self
            // Capsule-only (`shouldReceive`). Cancelling the scroll view's
            // remaining touches after `.began` must not apply to card-body taps.
            pan.cancelsTouchesInView = true
            pan.maximumNumberOfTouches = 1
        }

        deinit {
            pan.view?.removeGestureRecognizer(pan)
            unlockOffsets()
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let deltaY = gesture.translation(in: nil).y
            switch gesture.state {
            case .began:
                dragging = true
                lockOffsets(from: gesture.view)
                restoreLockedOffsets()
                parent.onBegan()
                parent.onChanged(deltaY)
            case .changed:
                guard dragging else { return }
                restoreLockedOffsets()
                parent.onChanged(deltaY)
            case .ended:
                guard dragging else { return }
                dragging = false
                parent.onChanged(deltaY)
                unlockOffsets()
                parent.onEnded()
            case .cancelled, .failed:
                let wasDragging = dragging
                dragging = false
                unlockOffsets()
                if wasDragging {
                    parent.onCancel()
                }
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            parent.enabled
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.enabled else { return false }
            if let handle = handleView, handleHitsCapsule(touch, handle: handle) {
                return true
            }
            guard let scroll = gestureRecognizer.view as? UIScrollView else { return false }
            return CalendarLayout.touchHitsCapsule(
                CalendarLayout.hourContentPoint(touch: touch, in: scroll),
                capsule: parent.capsuleInContent
            )
        }

        /// UIKit frame of the 16pt overlay — not SwiftUI GeometryReader.
        private func handleHitsCapsule(_ touch: UITouch, handle: UIView) -> Bool {
            guard handle.window != nil else { return false }
            let host = handle.superview ?? handle
            let rect = CalendarLayout.durationHandleWindowRect(
                handleInWindow: handle.convert(handle.bounds, to: nil),
                hostInWindow: host.convert(host.bounds, to: nil)
            )
            return CalendarLayout.touchHitsCapsule(touch.location(in: nil), capsule: rect)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func lockOffsets(from view: UIView?) {
            guard lockedOffsets.isEmpty else { return }
            var found: [(UIScrollView, CGPoint)] = []
            var current = view
            while let node = current {
                if let scroll = node as? UIScrollView {
                    found.append((scroll, scroll.contentOffset))
                }
                current = node.superview
            }
            lockedOffsets = found
        }

        func restoreLockedOffsets() {
            for (scroll, offset) in lockedOffsets where scroll.contentOffset != offset {
                scroll.setContentOffset(offset, animated: false)
            }
        }

        func unlockOffsets() {
            restoreLockedOffsets()
            lockedOffsets = []
        }
    }

    final class DurationPanRecognizer: UIPanGestureRecognizer {
        weak var owner: Coordinator?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            owner?.lockOffsets(from: view)
            owner?.restoreLockedOffsets()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            owner?.restoreLockedOffsets()
            super.touchesMoved(touches, with: event)
            owner?.restoreLockedOffsets()
            // UIScrollView otherwise keeps a sibling pan at `.possible` for the
            // whole drag (`a0da6ed`): hours stay still and duration never commits.
            if state == .possible {
                let delta = translation(in: nil)
                if abs(delta.y) >= 8 {
                    state = .began
                }
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            // Fast drag that never left `.possible` until lift still has to
            // `.began` so `handlePan` writes translation and commits duration.
            if state == .possible, abs(translation(in: nil).y) >= 8 {
                state = .began
            }
            super.touchesEnded(touches, with: event)
            if state != .began && state != .changed && state != .ended {
                owner?.unlockOffsets()
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesCancelled(touches, with: event)
            owner?.unlockOffsets()
        }

        override func canPrevent(_ other: UIGestureRecognizer) -> Bool {
            // Only after `.began`. Always-true while `.possible` blocked the
            // hour pan from recognizing (`a0da6ed`) without writing duration.
            state == .began || state == .changed
        }

        override func canBePrevented(by other: UIGestureRecognizer) -> Bool {
            !(state == .began || state == .changed)
        }

        override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
            false
        }
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?
        private weak var installedOn: UIScrollView?
        private var installToken = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            ensureInstalled()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            ensureInstalled()
        }

        func ensureInstalled() {
            guard let coordinator else { return }
            if let scroll = nearestVerticalScrollView() {
                attach(coordinator.pan, to: scroll)
                return
            }
            installToken += 1
            let token = installToken
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.installToken else { return }
                self.retryInstall(token: token, remaining: 24)
            }
        }

        private func retryInstall(token: Int, remaining: Int) {
            guard token == installToken else { return }
            if let coordinator, let scroll = nearestVerticalScrollView() {
                attach(coordinator.pan, to: scroll)
                return
            }
            guard remaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                self?.retryInstall(token: token, remaining: remaining - 1)
            }
        }

        private func attach(_ pan: UIPanGestureRecognizer, to scroll: UIScrollView) {
            if installedOn !== scroll || pan.view !== scroll {
                pan.view?.removeGestureRecognizer(pan)
                scroll.addGestureRecognizer(pan)
                installedOn = scroll
            }
            // Re-apply every update — SwiftUI may replace the scroll pan.
            scroll.panGestureRecognizer.require(toFail: pan)
            isUserInteractionEnabled = false
        }

        /// Hour scroller — the view that is actually under the finger at the
        /// visible capsule. Never attach to the SwiftUI hosting slot.
        private func nearestVerticalScrollView() -> UIScrollView? {
            var view: UIView? = superview
            while let current = view {
                if let scroll = current as? UIScrollView,
                   scroll.bounds.height > 0,
                   scroll.contentSize.height > scroll.bounds.height + 1
                {
                    return scroll
                }
                view = current.superview
            }
            return nil
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            nil
        }
    }
}
