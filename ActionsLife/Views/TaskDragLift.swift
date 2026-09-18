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

/// Hour `UIScrollView` otherwise delays subview touches. Do **not** pin
/// `canCancelContentTouches = false` here — that stayed after the capsule
/// pan and froze hours (`b69d3c0`). The duration pan sets it only while
/// tracking. Do **not** set `isScrollEnabled = false`. `hitTest` is nil.
struct HourScrollTouchBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        uiView.apply()
    }

    final class BridgeView: UIView {
        private var token = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            apply()
        }

        func apply() {
            if configureHourScroller() { return }
            token += 1
            let current = token
            DispatchQueue.main.async { [weak self] in
                guard let self, current == self.token else { return }
                self.retry(token: current, remaining: 24)
            }
        }

        private func retry(token: Int, remaining: Int) {
            guard token == self.token else { return }
            if configureHourScroller() { return }
            guard remaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                self?.retry(token: token, remaining: remaining - 1)
            }
        }

        @discardableResult
        private func configureHourScroller() -> Bool {
            var current: UIView? = superview
            while let node = current {
                if let scroll = node as? UIScrollView,
                   scroll.bounds.height > 0,
                   scroll.contentSize.height > scroll.bounds.height + 1
                {
                    scroll.delaysContentTouches = false
                    return true
                }
                current = node.superview
            }
            return false
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            nil
        }
    }
}

/// Tap + duration pan on the hour `UIScrollView`. Empty-hour (nil `hitTest` /
/// hour grid) stays timed create (`6b5a0c4` / `0884a7e`). Painted card body
/// `hitTest` → Details. Painted 16pt capsule `hitTest` → `setDuration`.
/// `canCancelContentTouches = false` only while the capsule pan tracks.
/// Never `isScrollEnabled = false`. No TapView/HandleView. No `TimedCardLayout.place`.
struct HourDurationPanBridge: UIViewRepresentable {
    var enabled: Bool
    var liveColumns: () -> [CalendarLayout.HourCanvasColumn]
    var headerHeight: CGFloat
    var columnWidth: CGFloat
    var pixelsPerHour: Double
    var snap: Int
    var onTimedCreate: (_ dayISO: String, _ minutes: Int) -> Void
    var onOpenDetails: (_ taskID: String) -> Void
    var onBegan: (CalendarLayout.DurationCapsuleTarget) -> Void
    /// Same API Details uses for “30 minutes”: `setDuration(taskID, minutes:)`.
    var onChanged: (_ taskID: String, _ minutes: Double) -> Void
    var onEnded: (_ taskID: String, _ minutes: Double) -> Void
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
        context.coordinator.bindStoreWrites(from: self)
        if !context.coordinator.dragging {
            context.coordinator.pan.isEnabled = enabled
            context.coordinator.tap.isEnabled = enabled
        }
        uiView.coordinator = context.coordinator
        uiView.ensureInstalled()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HourDurationPanBridge
        let pan = DurationPanRecognizer()
        let tap = UITapGestureRecognizer()
        private(set) var dragging = false
        private var lockedOffsets: [(UIScrollView, CGPoint)] = []
        private var savedCancelContentTouches: [(UIScrollView, Bool)] = []
        private var pendingHit: CalendarLayout.DurationCapsuleTarget?
        private var claimedTarget: CalendarLayout.DurationCapsuleTarget?
        /// Copied at install so `touchesMoved` does not go through a stale
        /// `parent` or a pan that never `.changed` (`074335c` byte-identical).
        var writeDuration: ((_ taskID: String, _ minutes: Double) -> Void)?
        var commitDuration: ((_ taskID: String, _ minutes: Double) -> Void)?
        fileprivate var capturedTaskID: String?
        private var capturedStartDuration: Double = 30
        private var beganWindowY: CGFloat?
        /// Hour scroller the pan is installed on (`81ba98a` Details). Follow
        /// the capsule `UITouch` in window space after `.began` — do **not**
        /// put the pan on the window (`e728c7b` ate `calendar.timed.*` taps).
        fileprivate weak var hourScroll: UIScrollView?
        /// The capsule `UITouch` from `.began`. Sampled in window space
        /// until `.ended` / `.cancelled`, even +80 pt below the 39pt card.
        fileprivate weak var trackedTouch: UITouch?
        private var followLink: CADisplayLink?

        init(parent: HourDurationPanBridge) {
            self.parent = parent
            super.init()
            pan.owner = self
            pan.delegate = self
            bindStoreWrites(from: parent)
            // False so a tap on empty hour / title still reaches the recognizers
            // (`605f886` cancelled SpatialTap and create went all-day).
            pan.cancelsTouchesInView = false
            tap.addTarget(self, action: #selector(handleTap(_:)))
            tap.delegate = self
            tap.cancelsTouchesInView = true
            tap.numberOfTapsRequired = 1
        }

        deinit {
            stopFollowingTouch()
            pan.view?.removeGestureRecognizer(pan)
            tap.view?.removeGestureRecognizer(tap)
            unlockOffsets()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.enabled, !dragging, let scroll = gesture.view as? UIScrollView else { return }
            switch canvasHit(in: scroll, locationInScroll: gesture.location(in: scroll)) {
            case .emptyHour(let dayISO, let minutes):
                parent.onTimedCreate(dayISO, minutes)
            case .blockBody(let taskID):
                parent.onOpenDetails(taskID)
            default:
                break
            }
        }

        func canvasHit(in scroll: UIScrollView, locationInScroll: CGPoint) -> CalendarLayout.HourCanvasHit? {
            let hitView = CalendarLayout.hourScrollHitView(
                in: scroll,
                locationInScroll: locationInScroll
            )
            if let painted = CalendarLayout.paintedCardHit(
                from: hitView,
                locationInScroll: locationInScroll,
                in: scroll
            ) {
                switch painted {
                case .blockBody(let taskID):
                    return .blockBody(taskID: taskID)
                case .capsule(let taskID):
                    return .capsule(capsuleTarget(taskID: taskID))
                }
            }
            // `6b5a0c4` empty-hour path — nil / hour-grid `hitTest`.
            return CalendarLayout.hourCanvasHit(
                contentPoint: CalendarLayout.blockFramePoint(
                    locationInScroll: locationInScroll,
                    scroll: scroll,
                    headerHeight: parent.headerHeight
                ),
                columns: parent.liveColumns(),
                columnWidth: parent.columnWidth,
                pixelsPerHour: parent.pixelsPerHour,
                snap: parent.snap
            )
        }

        func capsuleTarget(taskID: String) -> CalendarLayout.DurationCapsuleTarget {
            for (index, column) in parent.liveColumns().enumerated() {
                if let event = column.events.first(where: { $0.task.id == taskID }) {
                    return CalendarLayout.DurationCapsuleTarget(
                        taskID: taskID,
                        duration: event.task.duration,
                        rect: CalendarLayout.durationCapsuleRect(
                            columnIndex: index,
                            columnWidth: parent.columnWidth,
                            event: event
                        )
                    )
                }
            }
            return CalendarLayout.DurationCapsuleTarget(taskID: taskID, duration: 30, rect: .zero)
        }

        func bindStoreWrites(from parent: HourDurationPanBridge) {
            writeDuration = parent.onChanged
            commitDuration = parent.onEnded
        }

        func refreshStoreWrites() {
            bindStoreWrites(from: parent)
        }

        /// Handle follow must have a live `setDuration` (`81d22bb` pin-only).
        func hasLiveSetDurationCallback() -> Bool {
            writeDuration != nil
        }

        /// minutes = start + (location.y − began.y) / hourHeight * 60.
        func minutesFromBegan(locationY: CGFloat) -> Double {
            let began = beganWindowY ?? locationY
            return CalendarLayout.durationFromLocationDelta(
                start: capturedStartDuration,
                locationDeltaY: locationY - began,
                pixelsPerHour: parent.pixelsPerHour
            )
        }

        func captureCapsule(from scroll: UIScrollView?, touch: UITouch) {
            beganWindowY = touch.location(in: touch.window ?? scroll).y
            trackedTouch = touch
            // 16pt handle only (`28ee931` tap path). Do not bind to the
            // whole `calendar.timed.*` card / StaticText title.
            if let scroll {
                let location = touch.location(in: scroll)
                let view = CalendarLayout.hourScrollHitView(in: scroll, locationInScroll: location)
                if let painted = CalendarLayout.paintedCardHit(
                    from: view,
                    locationInScroll: location,
                    in: scroll
                ), case .capsule(let taskID) = painted {
                    capturedTaskID = taskID
                    capturedStartDuration = capsuleTarget(taskID: taskID).duration
                }
            }
            if capturedTaskID == nil, let hit = pendingHit ?? claimedTarget {
                capturedTaskID = hit.taskID
                capturedStartDuration = hit.duration
            }
            if capturedTaskID != nil {
                beginFollowing(touch)
            }
        }

        /// XCUITest / unit hook: same path `touchesMoved` uses after the
        /// finger leaves the 16pt capsule.
        func startWindowFollow(taskID: String, startDuration: Double, beganWindowY: CGFloat) {
            capturedTaskID = taskID
            capturedStartDuration = startDuration
            self.beganWindowY = beganWindowY
        }

        func followWindowY(_ windowY: CGFloat, ended: Bool) {
            writeStoreDuration(locationY: windowY, ended: ended)
        }

        func beginFollowing(_ touch: UITouch) {
            trackedTouch = touch
            guard followLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(sampleTrackedTouch))
            link.add(to: .main, forMode: .common)
            followLink = link
        }

        /// The recognizer can die when the finger leaves the 16pt band
        /// while the `UITouch` is still down (`28ee931` froze at 35 min).
        func shouldKeepFollowing(_ touch: UITouch) -> Bool {
            guard capturedTaskID != nil else { return false }
            switch touch.phase {
            case .began, .moved, .stationary:
                return true
            default:
                return false
            }
        }

        func stopFollowingTouch() {
            followLink?.invalidate()
            followLink = nil
            trackedTouch = nil
        }

        /// Keep writing window Y if `touchesMoved` is skipped after the
        /// finger leaves the 16pt handle. Same `UITouch`, window space.
        @objc func sampleTrackedTouch() {
            guard let touch = trackedTouch, capturedTaskID != nil else { return }
            let y = touch.location(in: touch.window).y
            switch touch.phase {
            case .began, .moved, .stationary:
                writeStoreDuration(locationY: y, ended: false)
                restoreLockedOffsets()
            case .ended, .cancelled:
                writeStoreDuration(locationY: y, ended: true)
                clearCapsuleCapture()
                dropClaim()
            default:
                break
            }
        }

        /// Direct store write from `touchesMoved` / `touchesEnded`.
        func writeStoreDuration(locationY: CGFloat, ended: Bool) {
            refreshStoreWrites()
            guard let taskID = capturedTaskID, !taskID.isEmpty else { return }
            let liveWrite = writeDuration ?? parent.onChanged
            let liveCommit = commitDuration ?? parent.onEnded
            dragging = true
            restoreLockedOffsets()
            let live = minutesFromBegan(locationY: locationY)
            if ended {
                let snapped = CalendarLayout.snapDuration(live, snap: parent.snap)
                invokeStoreWrite(liveCommit, taskID: taskID, minutes: snapped)
            } else {
                invokeStoreWrite(liveWrite, taskID: taskID, minutes: live)
            }
        }

        private func invokeStoreWrite(
            _ write: ((_ taskID: String, _ minutes: Double) -> Void)?,
            taskID: String,
            minutes: Double
        ) {
            guard let write else { return }
            let id = taskID
            let mins = minutes
            let run = { write(id, mins) }
            if Thread.isMainThread {
                run()
            } else {
                DispatchQueue.main.sync(execute: run)
            }
        }

        func applyLocationDelta(_ deltaY: CGFloat) {
            let y = (beganWindowY ?? 0) + deltaY
            writeStoreDuration(locationY: y, ended: false)
        }

        func durationPanEnded(deltaY: CGFloat) {
            if capturedTaskID != nil {
                let y = (beganWindowY ?? 0) + deltaY
                writeStoreDuration(locationY: y, ended: true)
            }
            clearCapsuleCapture()
            dropClaim()
        }

        func clearCapsuleCapture() {
            dragging = false
            pendingHit = nil
            claimedTarget = nil
            capturedTaskID = nil
            beganWindowY = nil
            stopFollowingTouch()
        }

        func durationPanCancelled() {
            let wasDragging = dragging
            dragging = false
            pendingHit = nil
            claimedTarget = nil
            capturedTaskID = nil
            beganWindowY = nil
            stopFollowingTouch()
            dropClaim()
            if wasDragging {
                parent.onCancel()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            parent.enabled || dragging
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.enabled || dragging else { return false }
            let scroll = hourScroll ?? gestureRecognizer.view as? UIScrollView
            guard let scroll else { return false }
            let hit = canvasHit(in: scroll, locationInScroll: touch.location(in: scroll))
            // Card body `calendar.timed.*` must reach Details (`e728c7b`
            // window pan + capturedTaskID stole the tap). Never deny the
            // tap because a capsule id is pending.
            if gestureRecognizer === tap {
                if dragging { return false }
                switch hit {
                case .emptyHour, .blockBody:
                    return true
                default:
                    return false
                }
            }
            if gestureRecognizer === pan {
                if dragging { return true }
                // Capsule / 16pt handle only — never the title StaticText
                // (`b8f1337` card-wide claim ate Details).
                if case .capsule(let target) = hit {
                    pendingHit = target
                    claimedTarget = target
                    return true
                }
                pendingHit = nil
                claimedTarget = nil
                return false
            }
            return false
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
            var saved: [(UIScrollView, Bool)] = []
            var current = view
            while let node = current {
                if let scroll = node as? UIScrollView {
                    saved.append((scroll, scroll.canCancelContentTouches))
                    scroll.canCancelContentTouches = false
                    scroll.delaysContentTouches = false
                    found.append((scroll, scroll.contentOffset))
                }
                current = node.superview
            }
            lockedOffsets = found
            savedCancelContentTouches = saved
        }

        func restoreLockedOffsets() {
            for (scroll, offset) in lockedOffsets where scroll.contentOffset != offset {
                scroll.setContentOffset(offset, animated: false)
            }
        }

        /// Unpin `contentOffset` and restore `canCancelContentTouches` so hours
        /// can scroll again (`94e965c`). Never leave this lock after `.ended`
        /// / `.cancelled`. Never `isScrollEnabled = false`.
        func dropClaim() {
            restoreLockedOffsets()
            for (scroll, previous) in savedCancelContentTouches {
                scroll.canCancelContentTouches = previous
            }
            savedCancelContentTouches = []
            lockedOffsets = []
        }

        func unlockOffsets() {
            dropClaim()
        }
    }

    /// Writes `setDuration` from `touchesMoved` / `touchesEnded` using
    /// window `location.y − began.y` and the capsule UIView’s `task.id`.
    /// Delivery continues after the finger leaves the 16pt capsule.
    final class DurationPanRecognizer: UIGestureRecognizer {
        weak var owner: Coordinator?

        override func reset() {
            super.reset()
        }

        private func windowY(of touch: UITouch) -> CGFloat {
            let space: UIView? = touch.window ?? view?.window ?? view
            return touch.location(in: space).y
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            guard touches.count == 1, let touch = touches.first else {
                state = .failed
                owner?.unlockOffsets()
                return
            }
            let scroll = owner?.hourScroll
            owner?.lockOffsets(from: scroll ?? view)
            owner?.captureCapsule(from: scroll, touch: touch)
            owner?.restoreLockedOffsets()
            if owner?.capturedTaskID != nil {
                state = .began
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesMoved(touches, with: event)
            // Follow the capsule `UITouch` in window space — not handle-local.
            // Must still run when the finger is +80 pt below the 39pt card.
            let touch = owner?.trackedTouch
                ?? touches.first(where: { $0 === owner?.trackedTouch })
                ?? touches.first
            guard let touch else { return }
            owner?.restoreLockedOffsets()
            if state == .began || state == .changed {
                state = .changed
            }
            owner?.followWindowY(windowY(of: touch), ended: false)
            owner?.restoreLockedOffsets()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            let touch = owner?.trackedTouch ?? touches.first
            if let touch {
                owner?.followWindowY(windowY(of: touch), ended: true)
            }
            owner?.clearCapsuleCapture()
            owner?.dropClaim()
            cancelsTouchesInView = false
            if state == .began || state == .changed {
                state = .ended
            } else {
                state = .failed
            }
            super.touchesEnded(touches, with: event)
            owner?.unlockOffsets()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            let touch = owner?.trackedTouch ?? touches.first
            // Recognizer cancelled at the handle edge; the finger may still
            // be down. Keep sampling window Y → setDuration until the
            // UITouch actually ends (`28ee931` committed 35 min here).
            if let touch, owner?.shouldKeepFollowing(touch) == true {
                owner?.followWindowY(windowY(of: touch), ended: false)
                state = .cancelled
                super.touchesCancelled(touches, with: event)
                return
            }
            if let touch, owner?.capturedTaskID != nil {
                owner?.followWindowY(windowY(of: touch), ended: true)
            }
            owner?.clearCapsuleCapture()
            owner?.dropClaim()
            cancelsTouchesInView = false
            state = .cancelled
            super.touchesCancelled(touches, with: event)
            owner?.unlockOffsets()
        }

        override func canPrevent(_ other: UIGestureRecognizer) -> Bool {
            owner?.dragging == true
        }

        override func canBePrevented(by other: UIGestureRecognizer) -> Bool {
            owner?.dragging != true
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
                attach(coordinator, to: scroll)
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
                attach(coordinator, to: scroll)
                return
            }
            guard remaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                self?.retryInstall(token: token, remaining: remaining - 1)
            }
        }

        private func attach(_ coordinator: Coordinator, to scroll: UIScrollView) {
            let pan = coordinator.pan
            let tap = coordinator.tap
            coordinator.hourScroll = scroll
            // Pan + tap on the hour scroller (`81ba98a` Details). Follow the
            // capsule UITouch in window space after `.began` — do not attach
            // the pan to the window (`e728c7b` ate `calendar.timed.*` taps).
            if installedOn !== scroll || pan.view !== scroll {
                pan.view?.removeGestureRecognizer(pan)
                tap.view?.removeGestureRecognizer(tap)
                scroll.addGestureRecognizer(pan)
                scroll.addGestureRecognizer(tap)
                installedOn = scroll
            }
            tap.require(toFail: pan)
            scroll.panGestureRecognizer.require(toFail: pan)
            scroll.delaysContentTouches = false
            coordinator.bindStoreWrites(from: coordinator.parent)
            isUserInteractionEnabled = false
        }

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

/// Pins ancestor `UIScrollView` contentOffsets once a duration drag
/// is **active**. Never sets `isScrollEnabled = false` on touch-down
/// (`a0da6ed` cancelled the pan). Does not flip `pointerCaptured` /
/// `scrollDisabled` (that rebuilds the hour scroller).
struct ScrollOffsetLockBridge: UIViewRepresentable {
    var locked: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        context.coordinator.view = uiView
        context.coordinator.setLocked(locked)
    }

    final class Coordinator: NSObject {
        weak var view: BridgeView?
        private var frozen: [(UIScrollView, CGPoint)] = []
        private var link: CADisplayLink?
        private var isLocked = false

        deinit {
            stopLink()
        }

        func setLocked(_ locked: Bool) {
            if locked {
                isLocked = true
                if frozen.isEmpty {
                    capture()
                }
                restore()
                startLink()
            } else {
                isLocked = false
                stopLink()
                restore()
                frozen = []
            }
        }

        private func capture() {
            var found: [(UIScrollView, CGPoint)] = []
            var current: UIView? = view
            while let node = current {
                if let scroll = node as? UIScrollView {
                    found.append((scroll, scroll.contentOffset))
                }
                current = node.superview
            }
            frozen = found
        }

        @objc func tick() {
            if frozen.isEmpty {
                capture()
            }
            restore()
        }

        private func restore() {
            for (scroll, offset) in frozen where scroll.contentOffset != offset {
                scroll.setContentOffset(offset, animated: false)
            }
        }

        private func startLink() {
            guard link == nil else { return }
            let displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink.add(to: .main, forMode: .common)
            link = displayLink
        }

        private func stopLink() {
            link?.invalidate()
            link = nil
        }
    }

    final class BridgeView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            nil
        }
    }
}
