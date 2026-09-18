import CoreGraphics
import Foundation
import SwiftUI

/// Shared pointer session so split, scroll, and drag-drop cannot all handle one touch.
@Observable
final class HomeChrome {
    var isResizing = false
    var isLifting = false
    var pixelsPerHour: Double = 50
    var snapInterval = 15
    var zones: [DropZone] = []
    var drag: DragSession?

    var pointerCaptured: Bool { isResizing || isLifting || drag != nil }

    struct DropZone: Equatable {
        enum Kind: Equatable {
            case list
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
        var finger: CGPoint
        var grabOffset: CGSize
        var ghostSize: CGSize
        var target: DropTarget = .none
    }

    enum DropTarget: Equatable {
        case none
        case list
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

    func beginDrag(taskID: String, name: String, duration: Double, finger: CGPoint, frame: CGRect) {
        drag = DragSession(
            taskID: taskID,
            name: name,
            duration: duration,
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
            ghostSize: session.ghostSize,
            zones: zones,
            pixelsPerHour: pixelsPerHour,
            snap: snapInterval
        )
        drag = session
    }

    func finishDrag() -> DropTarget {
        isLifting = false
        let target = drag?.target ?? .none
        drag = nil
        return target
    }

    func cancelDrag() {
        isLifting = false
        drag = nil
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
        drag?.target == .list
    }
}

enum DropMath {
    /// Same as the web `getLocalY`: clientY minus the canvas's on-screen top.
    /// The global frame already moves with scroll, so do not add scroll offset again.
    static func canvasY(globalY: CGFloat, canvasGlobalMinY: CGFloat) -> CGFloat {
        globalY - canvasGlobalMinY
    }

    static func target(
        ghostTop: CGPoint,
        ghostSize: CGSize,
        zones: [HomeChrome.DropZone],
        pixelsPerHour: Double,
        snap: Int
    ) -> HomeChrome.DropTarget {
        let probe = CGRect(x: ghostTop.x, y: ghostTop.y, width: max(ghostSize.width, 8), height: 2)
        var timed: HomeChrome.DropZone?
        var allDay: HomeChrome.DropZone?
        var list: HomeChrome.DropZone?
        for zone in zones where zone.frame.intersects(probe) {
            switch zone.kind {
            case .timed:
                timed = zone
            case .allDay:
                allDay = zone
            case .list:
                list = zone
            }
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
