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
/// hold begins and the pan cannot share the touch. `scrollDisabled` stays off
/// during a lift so `HomeChrome.edgeScrollDriver` can move the list.
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
                    onEnclosingScroll: { scroll in
                        chrome.bindScrollView(scroll, pane: fromCalendar ? .calendar : .list)
                    },
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

/// Captures the enclosing `UIScrollView` from **inside** scroll content
/// (ancestor walk). Overlay search cannot see a neighbor pane's scroller,
/// and a representable sitting *beside* UIScrollView never finds one.
struct ScrollViewBinder: UIViewRepresentable {
    var onFound: (UIScrollView) -> Void

    func makeUIView(context: Context) -> BinderView {
        let view = BinderView()
        view.onFound = onFound
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: BinderView, context: Context) {
        uiView.onFound = onFound
        uiView.probe()
    }

    final class BinderView: UIView {
        var onFound: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            probe()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            probe()
        }

        func probe() {
            let find = { [weak self] in
                guard let self else { return }
                if let scroll = Self.enclosingScrollView(from: self) {
                    self.onFound?(scroll)
                }
            }
            find()
            DispatchQueue.main.async(execute: find)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: find)
        }

        static func enclosingScrollView(from start: UIView) -> UIScrollView? {
            var view: UIView? = start
            while let current = view {
                if current is UIWindow { return nil }
                if let scroll = current as? UIScrollView { return scroll }
                view = current.superview
            }
            return nil
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}

/// Lives **inside** the pane `ScrollView` content. Binds that pane's
/// `UIScrollView` (ancestor walk, same path as the working lift recognizer)
/// and re-applies the driver's sticky offset after SwiftUI layout.
///
/// Do not overlay this on the pane: overlay DFS / neighbor search is how
/// `86933ab` and `0b7c5f5` failed to move the list. The display link lives
/// on `HomeChrome.edgeScrollDriver`, not here — InboxView does not read
/// `chrome.drag`, so `updateUIView` would never start a link on lift.
struct ScrollEdgeBridge: UIViewRepresentable {
    var chrome: HomeChrome
    var pane: HomeChrome.ScrollPane

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
        uiView.bindEnclosing()
    }

    final class BridgeView: UIView {
        var chrome: HomeChrome?
        var pane: HomeChrome.ScrollPane = .list

        override func didMoveToWindow() {
            super.didMoveToWindow()
            bindEnclosing()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            bindEnclosing()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            bindEnclosing()
            chrome?.reapplyEdgeScrollOffsets()
        }

        func bindEnclosing() {
            guard let chrome, let scroll = ScrollViewBinder.BinderView.enclosingScrollView(from: self) else {
                return
            }
            chrome.bindScrollView(scroll, pane: pane)
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}

/// Drives list/calendar autoscroll while a row is lifted. Retained by
/// `HomeChrome` so it keeps ticking during a still hold even when SwiftUI
/// does not call `updateUIView` on pane overlays.
final class EdgeScrollDriver: NSObject {
    weak var chrome: HomeChrome?
    private var displayLink: CADisplayLink?
    private var listSticky: CGPoint?
    private var calendarSticky: CGPoint?

    deinit { stop() }

    func setActive(_ active: Bool) {
        if active {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        listSticky = nil
        calendarSticky = nil
    }

    func reapply() {
        guard chrome?.drag != nil else { return }
        if let scroll = chrome?.listScrollView, let listSticky {
            HomeChrome.applyContentOffset(listSticky, on: scroll)
        }
        if let scroll = chrome?.calendarScrollView, let calendarSticky {
            HomeChrome.applyContentOffset(calendarSticky, on: scroll)
        }
    }

    private func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc func tick() {
        guard let chrome, chrome.drag != nil, let finger = chrome.drag?.finger else { return }
        chrome.updateEdgeScroll(finger: finger)
        step(pane: .list, finger: finger)
        step(pane: .calendar, finger: finger)
    }

    private func step(pane: HomeChrome.ScrollPane, finger: CGPoint) {
        guard let chrome else { return }
        let viewport = pane == .list ? chrome.listPane : chrome.calendarPane
        let axes: DropMath.AxisSet = pane == .list ? [.vertical] : [.horizontal, .vertical]
        let delta = DropMath.edgeScrollDelta(
            finger: finger,
            viewport: viewport,
            band: DropMath.edgeBand(for: viewport),
            step: HomeChrome.edgeStep,
            axes: axes,
            ghostTop: chrome.ghostTop,
            ghostSize: chrome.drag?.ghostSize ?? .zero
        )
        guard let scroll = pane == .list ? chrome.listScrollView : chrome.calendarScrollView,
              scroll.window != nil
        else { return }

        if delta == .zero {
            let current = scroll.contentOffset
            if pane == .list { listSticky = current } else { calendarSticky = current }
            return
        }

        let inset = scroll.adjustedContentInset
        let extent = Self.contentSize(of: scroll)
        let current = (pane == .list ? listSticky : calendarSticky) ?? scroll.contentOffset
        let next = HomeChrome.clampedContentOffset(
            current: current,
            adding: delta,
            contentSize: extent,
            viewportSize: scroll.bounds.size,
            insetTop: inset.top,
            insetLeft: inset.left,
            insetBottom: inset.bottom,
            insetRight: inset.right
        )
        HomeChrome.applyContentOffset(next, on: scroll)
        if pane == .list { listSticky = next } else { calendarSticky = next }
        DispatchQueue.main.async { [weak self, weak scroll] in
            guard let self, let scroll, self.chrome?.drag != nil else { return }
            let sticky = pane == .list ? self.listSticky : self.calendarSticky
            if let sticky {
                HomeChrome.applyContentOffset(sticky, on: scroll)
            }
        }
    }

    /// SwiftUI sometimes reports `contentSize == bounds` even when the hosting
    /// subview is taller (Visa children below the fold). Measure subviews.
    static func contentSize(of scroll: UIScrollView) -> CGSize {
        var width = scroll.contentSize.width
        var height = scroll.contentSize.height
        for sub in scroll.subviews {
            width = max(width, sub.frame.maxX)
            height = max(height, sub.frame.maxY)
            for nested in sub.subviews {
                width = max(width, nested.frame.maxX)
                height = max(height, nested.frame.maxY)
            }
        }
        return CGSize(width: width, height: height)
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
    var onEnclosingScroll: (UIScrollView) -> Void
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
                    parent.onEnclosingScroll(scroll)
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
                if let scroll = current as? UIScrollView {
                    coordinator?.parent.onEnclosingScroll(scroll)
                    return current
                }
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
