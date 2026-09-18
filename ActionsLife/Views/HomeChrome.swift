import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Shared pointer session so split, scroll, and drag-drop cannot all handle one touch.
///
/// `isResizing` must only be set by `SplitResizeBridge`, which clears it on
/// ended **and** cancelled/failed. A stuck `true` used to freeze both panes
/// via `scrollDisabled`. List autoscroll must **not** toggle `scrollDisabled`
/// during a lift — SwiftUI resets `contentOffset` when that flips.
@Observable
final class HomeChrome {
    static let holdDelay: TimeInterval = 0.15
    static let touchSlop: CGFloat = 5
    /// Legacy Expo constant. Autoscroll uses `DropMath.edgeBand(for:)` (visible
    /// pane fraction) so a hold on Connect above Visa still scrolls.
    static let edgeBand: CGFloat = 44
    static let edgeStep: CGFloat = 16
    static let splitHandle: CGFloat = 36
    static let splitMinPane: CGFloat = 48

    var isResizing = false
    var isLifting = false
    var pixelsPerHour: Double = 50
    var snapInterval = 15
    var zones: [DropZone] = []
    var drag: DragSession?

    /// Global frames of the calendar / list panes (for clipping + edge scroll).
    var calendarPane: CGRect = .null
    var listPane: CGRect = .null
    var homeFrame: CGRect = .null

    /// Bound from *inside* each pane's scroll content (and from the lift
    /// recognizer's enclosing `UIScrollView`). Overlay DFS picks neighbors.
    @ObservationIgnored
    weak var listScrollView: UIScrollView?
    @ObservationIgnored
    weak var calendarScrollView: UIScrollView?

    /// Owns the drag-time `CADisplayLink`. Must not live on a SwiftUI overlay
    /// whose `updateUIView` never sees `drag` (InboxView does not read it).
    @ObservationIgnored
    let edgeScrollDriver = EdgeScrollDriver()

    enum ScrollPane {
        case list
        case calendar
    }

    init() {
        edgeScrollDriver.chrome = self
    }

    deinit {
        edgeScrollDriver.stop()
    }

    func bindScrollView(_ scroll: UIScrollView, pane: ScrollPane) {
        switch pane {
        case .list:
            listScrollView = scroll
        case .calendar:
            calendarScrollView = scroll
        }
    }

    func reapplyEdgeScrollOffsets() {
        edgeScrollDriver.reapply()
    }

    /// Requested edge-scroll deltas consumed by scroll views each tick.
    var calendarScrollDelta: CGSize = .zero
    var listScrollDelta: CGSize = .zero
    /// Bumped every edge-scroll tick so bridges re-apply a steady delta.
    var edgeScrollGeneration: Int = 0

    var pointerCaptured: Bool { isResizing || isLifting || drag != nil }

    struct DropZone: Equatable {
        enum Kind: Equatable {
            case list
            case listSlot(parentID: String, index: Int)
            case nest(String)
            case allDay(String)
            case timed(String)
        }

        var kind: Kind
        var frame: CGRect
    }

    struct DragSession: Equatable {
        var taskID: String
        var name: String
        var duration: Double
        var fromCalendar: Bool
        var finger: CGPoint
        var grabOffset: CGSize
        var ghostSize: CGSize
        var target: DropTarget = .none
    }

    enum DropTarget: Equatable {
        case none
        case list
        case listSlot(parentID: String, index: Int)
        case nest(String)
        case allDay(String)
        case timed(dayISO: String, minutes: Int)
    }

    var ghostTop: CGPoint {
        guard let drag else { return .zero }
        return CGPoint(
            x: drag.finger.x - drag.grabOffset.width,
            y: drag.finger.y - drag.grabOffset.height
        )
    }

    func beginDrag(
        taskID: String,
        name: String,
        duration: Double,
        finger: CGPoint,
        frame: CGRect,
        fromCalendar: Bool = false
    ) {
        isLifting = true
        drag = DragSession(
            taskID: taskID,
            name: name,
            duration: duration,
            fromCalendar: fromCalendar,
            finger: finger,
            grabOffset: CGSize(width: finger.x - frame.minX, height: finger.y - frame.minY),
            ghostSize: CGSize(width: max(frame.width, 80), height: max(frame.height, 36))
        )
        moveDrag(finger: finger)
    }

    func moveDrag(finger: CGPoint) {
        guard var session = drag else { return }
        session.finger = finger
        session.target = DropMath.target(
            ghostTop: CGPoint(
                x: finger.x - session.grabOffset.width,
                y: finger.y - session.grabOffset.height
            ),
            finger: finger,
            ghostSize: session.ghostSize,
            zones: zones,
            draggingID: session.taskID,
            fromCalendar: session.fromCalendar,
            calendarPane: calendarPane,
            listPane: listPane,
            pixelsPerHour: pixelsPerHour,
            snap: snapInterval
        )
        drag = session
        updateEdgeScroll(finger: finger)
        edgeScrollDriver.setActive(true)
    }

    func finishDrag() -> DropTarget {
        isLifting = false
        calendarScrollDelta = .zero
        listScrollDelta = .zero
        edgeScrollDriver.setActive(false)
        let target = drag?.target ?? .none
        drag = nil
        return target
    }

    func cancelDrag() {
        isLifting = false
        calendarScrollDelta = .zero
        listScrollDelta = .zero
        edgeScrollDriver.setActive(false)
        drag = nil
    }

    func updateEdgeScroll(finger: CGPoint) {
        let ghost = drag.map {
            CGPoint(x: $0.finger.x - $0.grabOffset.width, y: $0.finger.y - $0.grabOffset.height)
        }
        let ghostSize = drag?.ghostSize ?? .zero
        let listBand = DropMath.edgeBand(for: listPane)
        let calendarBand = DropMath.edgeBand(for: calendarPane)
        calendarScrollDelta = DropMath.edgeScrollDelta(
            finger: finger,
            viewport: calendarPane,
            band: calendarBand,
            step: Self.edgeStep,
            axes: [.horizontal, .vertical],
            ghostTop: ghost,
            ghostSize: ghostSize
        )
        listScrollDelta = DropMath.edgeScrollDelta(
            finger: finger,
            viewport: listPane,
            band: listBand,
            step: Self.edgeStep,
            axes: [.vertical],
            ghostTop: ghost,
            ghostSize: ghostSize
        )
        if calendarScrollDelta != .zero || listScrollDelta != .zero {
            edgeScrollGeneration &+= 1
        }
    }

    func timedPreview(for dayISO: String) -> (y: CGFloat, height: CGFloat)? {
        guard let drag, case .timed(let iso, let minutes) = drag.target, iso == dayISO else { return nil }
        let height = max(
            CalendarLayout.minimumEventHeight,
            CGFloat(max(drag.duration, 15) / 60) * CalendarLayout.hourHeight(pixelsPerHour: pixelsPerHour)
        )
        return (CalendarLayout.y(fromMinutes: minutes, pixelsPerHour: pixelsPerHour), height)
    }

    func showsAllDayPreview(for dayISO: String) -> Bool {
        guard let drag else { return false }
        if case .allDay(let iso) = drag.target { return iso == dayISO }
        return false
    }

    func showsListPreview() -> Bool {
        switch drag?.target {
        case .list, .listSlot, .nest:
            return true
        default:
            return false
        }
    }

    func showsSlotPreview(parentID: String, index: Int) -> Bool {
        drag?.target == .listSlot(parentID: parentID, index: index)
    }

    func showsNestPreview(for taskID: String) -> Bool {
        drag?.target == .nest(taskID)
    }

    static func clampSplitFraction(_ split: Double, height: CGFloat) -> Double {
        DropMath.clampSplitFraction(
            split,
            height: height,
            handle: splitHandle,
            minPane: splitMinPane
        )
    }

    /// Programmatic offset for a SwiftUI `UIScrollView`. Do not flip
    /// `isScrollEnabled` — that rebuilds the representable and resets offset.
    static func clampedContentOffset(
        current: CGPoint,
        adding delta: CGSize,
        contentSize: CGSize,
        viewportSize: CGSize,
        insetTop: CGFloat = 0,
        insetLeft: CGFloat = 0,
        insetBottom: CGFloat = 0,
        insetRight: CGFloat = 0
    ) -> CGPoint {
        let minX = -insetLeft
        let minY = -insetTop
        let maxX = max(minX, contentSize.width - viewportSize.width + insetRight)
        let maxY = max(minY, contentSize.height - viewportSize.height + insetBottom)
        return CGPoint(
            x: min(maxX, max(minX, current.x + delta.width)),
            y: min(maxY, max(minY, current.y + delta.height))
        )
    }

    static func applyContentOffset(_ offset: CGPoint, on scroll: UIScrollView) {
        guard scroll.contentOffset != offset else { return }
        UIView.performWithoutAnimation {
            scroll.setContentOffset(offset, animated: false)
        }
    }
}

enum DropMath {
    struct AxisSet: OptionSet {
        let rawValue: Int
        static let horizontal = AxisSet(rawValue: 1 << 0)
        static let vertical = AxisSet(rawValue: 1 << 1)
    }

    /// Bottom/top band of the **visible pane** (not a fixed 44pt). A hold over
    /// the last on-screen row (Connect above Visa) must autoscroll.
    static func edgeBand(for viewport: CGRect, floor: CGFloat = 64) -> CGFloat {
        guard !viewport.isNull, viewport.height > 1 else { return floor }
        return min(viewport.height * 0.5, max(floor, viewport.height * 0.25))
    }

    /// Web `getLocalY`: **finger** (clientY), not ghost-top, minus the canvas
    /// element's global top. The canvas frame moves with scroll; do not clip it
    /// to the pane first or hour 9 in a 9–16 viewport maps to ~04:00.
    static func canvasY(globalY: CGFloat, canvasGlobalMinY: CGFloat) -> CGFloat {
        globalY - canvasGlobalMinY
    }

    /// Web mobile `ListCalendar.safe`: list height ∈ [minPane, full remaining].
    /// Calendar may collapse to 0 so the list can go fullscreen; list keeps a 48pt floor.
    static func clampSplitFraction(
        _ split: Double,
        height: CGFloat,
        handle: CGFloat,
        minPane: CGFloat
    ) -> Double {
        let remaining = height - handle
        guard remaining > 0 else { return min(1, max(0, split)) }
        if remaining <= minPane { return 1 }
        let minF = Double(minPane / remaining)
        return min(1, max(minF, split))
    }

    /// Expo `clipRectToWindow` — drop empty clips.
    static func clip(_ rect: CGRect, to pane: CGRect) -> CGRect? {
        guard !pane.isNull, !pane.isEmpty else { return rect }
        let clipped = rect.intersection(pane)
        guard clipped.width > 2, clipped.height > 2 else { return nil }
        return clipped
    }

    /// Expo `edgeScrollDelta`.
    ///
    /// A lift held at the list bottom often has the **finger** on/past `maxY`
    /// (home indicator, XCUITest y=0.94) while the **ghost** sits a row above.
    /// Treat finger or ghost in the band, and finger just outside the pane, as
    /// an edge — `CGRect.contains` is max-edge exclusive.
    static func edgeScrollDelta(
        finger: CGPoint,
        viewport: CGRect,
        band: CGFloat,
        step: CGFloat,
        axes: AxisSet,
        ghostTop: CGPoint? = nil,
        ghostSize: CGSize = .zero
    ) -> CGSize {
        guard !viewport.isNull, !viewport.isEmpty else { return .zero }
        let ghostRect: CGRect? = ghostTop.map {
            CGRect(
                origin: $0,
                size: ghostSize.width > 1 ? ghostSize : CGSize(width: 8, height: 36)
            )
        }
        let xAligned = finger.x >= viewport.minX - 24 && finger.x <= viewport.maxX + 24
        let yAligned = finger.y >= viewport.minY - 24 && finger.y <= viewport.maxY + 24
        let fingerNearPane = viewport.insetBy(dx: -24, dy: -40).contains(finger)
            || (xAligned && (finger.y < viewport.minY || finger.y > viewport.maxY))
            || (yAligned && (finger.x < viewport.minX || finger.x > viewport.maxX))
        let ghostNearPane = ghostRect?.intersects(viewport.insetBy(dx: -8, dy: -8)) ?? false
        guard fingerNearPane || ghostNearPane else { return .zero }

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if axes.contains(.vertical) {
            let ghostMinY = ghostRect?.minY ?? .greatestFiniteMagnitude
            let ghostMaxY = ghostRect?.maxY ?? -.greatestFiniteMagnitude
            if finger.y < viewport.minY + band || finger.y < viewport.minY || ghostMinY < viewport.minY + band {
                dy = -step
            } else if finger.y > viewport.maxY - band || finger.y > viewport.maxY || ghostMaxY > viewport.maxY - band {
                dy = step
            }
        }
        if axes.contains(.horizontal) {
            if finger.x < viewport.minX + band || finger.x < viewport.minX { dx = -step }
            else if finger.x > viewport.maxX - band || finger.x > viewport.maxX { dx = step }
        }
        return CGSize(width: dx, height: dy)
    }

    static func target(
        ghostTop: CGPoint,
        finger: CGPoint,
        ghostSize: CGSize,
        zones: [HomeChrome.DropZone],
        draggingID: String,
        fromCalendar: Bool,
        calendarPane: CGRect,
        listPane: CGRect,
        pixelsPerHour: Double,
        snap: Int
    ) -> HomeChrome.DropTarget {
        let listProbe = CGRect(x: ghostTop.x, y: ghostTop.y, width: max(ghostSize.width, 8), height: 2)
        let fingerProbe = CGRect(x: finger.x - 4, y: finger.y - 1, width: 8, height: 2)
        let fingerInCalendar = !calendarPane.isNull && calendarPane.insetBy(dx: 0, dy: -4).contains(finger)
        let fingerInList = !listPane.isNull && listPane.insetBy(dx: 0, dy: -4).contains(finger)
        let listEdgeScrolling = edgeScrollDelta(
            finger: finger,
            viewport: listPane,
            band: edgeBand(for: listPane),
            step: 1,
            axes: [.vertical],
            ghostTop: ghostTop,
            ghostSize: ghostSize
        ) != .zero

        var nest: HomeChrome.DropZone?
        var listSlot: HomeChrome.DropZone?
        var timed: HomeChrome.DropZone?
        var timedCanvasMinY: CGFloat?
        var allDay: HomeChrome.DropZone?
        var list: HomeChrome.DropZone?

        for zone in zones {
            let pane: CGRect
            switch zone.kind {
            case .list, .listSlot:
                pane = listPane
            case .nest:
                // Prefer the pane under the finger so list nests cannot steal calendar drops.
                if fingerInCalendar && !fingerInList {
                    pane = calendarPane
                } else if fingerInList && !fingerInCalendar {
                    pane = listPane
                } else {
                    pane = fromCalendar ? calendarPane : listPane
                }
            case .allDay, .timed:
                pane = calendarPane
            }

            // While the finger is clearly in one pane, ignore the other pane's zones.
            if fingerInCalendar && !fingerInList {
                switch zone.kind {
                case .list, .listSlot:
                    continue
                case .nest:
                    if !listPane.isNull,
                       listPane.contains(CGPoint(x: zone.frame.midX, y: zone.frame.midY)),
                       (calendarPane.isNull || !calendarPane.contains(CGPoint(x: zone.frame.midX, y: zone.frame.midY)))
                    {
                        continue
                    }
                default:
                    break
                }
            }
            if fingerInList && !fingerInCalendar {
                switch zone.kind {
                case .allDay, .timed:
                    continue
                default:
                    break
                }
            }

            guard let frame = clip(zone.frame, to: pane.isNull ? zone.frame : pane) else { continue }
            let probe: CGRect
            switch zone.kind {
            case .timed, .allDay:
                probe = fingerProbe
            default:
                probe = listProbe
            }
            // Inflate 1pt so probes on a pane's bottom edge still count (CGRect is edge-exclusive).
            guard frame.insetBy(dx: -1, dy: -1).intersects(probe) else { continue }

            switch zone.kind {
            case .nest(let id):
                guard id != draggingID else { continue }
                nest = HomeChrome.DropZone(kind: zone.kind, frame: frame)
            case .listSlot:
                listSlot = HomeChrome.DropZone(kind: zone.kind, frame: frame)
            case .timed:
                timed = HomeChrome.DropZone(kind: zone.kind, frame: frame)
                timedCanvasMinY = zone.frame.minY
            case .allDay:
                allDay = HomeChrome.DropZone(kind: zone.kind, frame: frame)
            case .list:
                list = HomeChrome.DropZone(kind: zone.kind, frame: frame)
            }
        }

        // Calendar finger: prefer timed/allDay/nest-cal over list.
        if fingerInCalendar {
            if let nest, case .nest(let taskID) = nest.kind {
                return .nest(taskID)
            }
            if let timed, case .timed(let dayISO) = timed.kind {
                return .timed(
                    dayISO: dayISO,
                    minutes: timedMinutes(
                        fingerY: finger.y,
                        canvasGlobalMinY: timedCanvasMinY ?? timed.frame.minY,
                        pixelsPerHour: pixelsPerHour,
                        snap: snap
                    )
                )
            }
            if let allDay, case .allDay(let dayISO) = allDay.kind {
                return .allDay(dayISO)
            }
        }

        // Holding a lifted row on the list edge autoscrolls; do not treat that
        // as a slot/nest drop (PR #4 reordered inside TO-DO instead of scrolling).
        if listEdgeScrolling {
            return .none
        }

        if let nest, case .nest(let taskID) = nest.kind {
            return .nest(taskID)
        }
        if let listSlot, case .listSlot(let parentID, let index) = listSlot.kind {
            return .listSlot(parentID: parentID, index: index)
        }
        if let timed, case .timed(let dayISO) = timed.kind {
            return .timed(
                dayISO: dayISO,
                minutes: timedMinutes(
                    fingerY: finger.y,
                    canvasGlobalMinY: timedCanvasMinY ?? timed.frame.minY,
                    pixelsPerHour: pixelsPerHour,
                    snap: snap
                )
            )
        }
        if let allDay, case .allDay(let dayISO) = allDay.kind {
            return .allDay(dayISO)
        }
        if list != nil {
            return .list
        }
        return .none
    }

    static func timedMinutes(
        fingerY: CGFloat,
        canvasGlobalMinY: CGFloat,
        pixelsPerHour: Double,
        snap: Int
    ) -> Int {
        let localY = canvasY(globalY: fingerY, canvasGlobalMinY: canvasGlobalMinY)
        return CalendarLayout.minutes(atY: localY, pixelsPerHour: pixelsPerHour, snap: snap)
    }
}
