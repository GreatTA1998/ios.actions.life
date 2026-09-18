import CoreGraphics
import Foundation
import SwiftUI

/// Shared pointer session so split, scroll, and drag-drop cannot all handle one touch.
@Observable
final class HomeChrome {
    static let holdDelay: TimeInterval = 0.15
    static let touchSlop: CGFloat = 5
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
    }

    func finishDrag() -> DropTarget {
        isLifting = false
        calendarScrollDelta = .zero
        listScrollDelta = .zero
        let target = drag?.target ?? .none
        drag = nil
        return target
    }

    func cancelDrag() {
        isLifting = false
        calendarScrollDelta = .zero
        listScrollDelta = .zero
        drag = nil
    }

    func updateEdgeScroll(finger: CGPoint) {
        calendarScrollDelta = DropMath.edgeScrollDelta(
            finger: finger,
            viewport: calendarPane,
            band: Self.edgeBand,
            step: Self.edgeStep,
            axes: [.horizontal, .vertical]
        )
        listScrollDelta = DropMath.edgeScrollDelta(
            finger: finger,
            viewport: listPane,
            band: Self.edgeBand,
            step: Self.edgeStep,
            axes: [.vertical]
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
}

enum DropMath {
    struct AxisSet: OptionSet {
        let rawValue: Int
        static let horizontal = AxisSet(rawValue: 1 << 0)
        static let vertical = AxisSet(rawValue: 1 << 1)
    }

    /// Same as the web `getLocalY`: clientY minus the canvas's on-screen top.
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
    static func edgeScrollDelta(
        finger: CGPoint,
        viewport: CGRect,
        band: CGFloat,
        step: CGFloat,
        axes: AxisSet
    ) -> CGSize {
        guard !viewport.isNull, !viewport.isEmpty else { return .zero }
        guard viewport.contains(finger) else { return .zero }
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if axes.contains(.vertical) {
            if finger.y < viewport.minY + band { dy = -step }
            else if finger.y > viewport.maxY - band { dy = step }
        }
        if axes.contains(.horizontal) {
            if finger.x < viewport.minX + band { dx = -step }
            else if finger.x > viewport.maxX - band { dx = step }
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
        let probe = CGRect(x: ghostTop.x, y: ghostTop.y, width: max(ghostSize.width, 8), height: 2)
        let fingerInCalendar = !calendarPane.isNull && calendarPane.insetBy(dx: 0, dy: -4).contains(finger)
        let fingerInList = !listPane.isNull && listPane.insetBy(dx: 0, dy: -4).contains(finger)

        var nest: HomeChrome.DropZone?
        var listSlot: HomeChrome.DropZone?
        var timed: HomeChrome.DropZone?
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
            // Inflate 1pt so ghost tops on a pane's bottom edge still count (CGRect is edge-exclusive).
            guard frame.insetBy(dx: -1, dy: -1).intersects(probe) else { continue }

            switch zone.kind {
            case .nest(let id):
                guard id != draggingID else { continue }
                nest = HomeChrome.DropZone(kind: zone.kind, frame: frame)
            case .listSlot:
                listSlot = HomeChrome.DropZone(kind: zone.kind, frame: frame)
            case .timed:
                timed = HomeChrome.DropZone(kind: zone.kind, frame: frame)
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
                let localY = canvasY(globalY: ghostTop.y, canvasGlobalMinY: timed.frame.minY)
                let minutes = CalendarLayout.minutes(atY: localY, pixelsPerHour: pixelsPerHour, snap: snap)
                return .timed(dayISO: dayISO, minutes: minutes)
            }
            if let allDay, case .allDay(let dayISO) = allDay.kind {
                return .allDay(dayISO)
            }
        }

        if let nest, case .nest(let taskID) = nest.kind {
            return .nest(taskID)
        }
        if let listSlot, case .listSlot(let parentID, let index) = listSlot.kind {
            return .listSlot(parentID: parentID, index: index)
        }
        if let timed, case .timed(let dayISO) = timed.kind {
            let localY = canvasY(globalY: ghostTop.y, canvasGlobalMinY: timed.frame.minY)
            let minutes = CalendarLayout.minutes(atY: localY, pixelsPerHour: pixelsPerHour, snap: snap)
            return .timed(dayISO: dayISO, minutes: minutes)
        }
        if let allDay, case .allDay(let dayISO) = allDay.kind {
            return .allDay(dayISO)
        }
        if list != nil {
            return .list
        }
        return .none
    }
}
