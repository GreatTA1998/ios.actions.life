import CoreGraphics
import Foundation
import UIKit

enum CalendarLayout {
    static let startHour = 0
    static let endHour = 24
    static let timeAxisWidth: CGFloat = 44
    static let minimumEventHeight: CGFloat = 28

    static func hourHeight(pixelsPerHour: Double) -> CGFloat {
        CGFloat(max(36, pixelsPerHour))
    }

    static func canvasHeight(pixelsPerHour: Double) -> CGFloat {
        CGFloat(endHour - startHour) * hourHeight(pixelsPerHour: pixelsPerHour)
    }

    static func hours() -> [Int] {
        Array(startHour..<endHour)
    }

    struct PlacedEvent: Identifiable, Equatable {
        var id: String { task.id }
        var task: TaskSnapshot
        var y: CGFloat
        var height: CGFloat
    }

    static func split(tasks: [TaskSnapshot]) -> (allDay: [TaskSnapshot], timed: [TaskSnapshot]) {
        var allDay: [TaskSnapshot] = []
        var timed: [TaskSnapshot] = []
        for task in tasks {
            if task.startTime.isEmpty {
                allDay.append(task)
            } else {
                timed.append(task)
            }
        }
        return (allDay, timed)
    }

    static func placeTimed(_ tasks: [TaskSnapshot], pixelsPerHour: Double) -> [PlacedEvent] {
        let hourH = hourHeight(pixelsPerHour: pixelsPerHour)
        return tasks.map { task in
            let startMinutes = DateISO.minutes(fromClock: task.startTime) ?? 0
            let clampedStart = min(max(startMinutes, 0), endHour * 60 - 1)
            let y = CGFloat(clampedStart - startHour * 60) / 60 * hourH
            let durationHeight = CGFloat(max(task.duration, 15) / 60) * hourH
            let height = min(max(minimumEventHeight, durationHeight), canvasHeight(pixelsPerHour: pixelsPerHour) - y)
            return PlacedEvent(task: task, y: y, height: height)
        }
    }

    /// Card frame height (matches DayColumnView `max(event.height, 36)`).
    static func blockFrameHeight(duration: Double, y: CGFloat, pixelsPerHour: Double) -> CGFloat {
        let hourH = hourHeight(pixelsPerHour: pixelsPerHour)
        let durationHeight = CGFloat(max(duration, 15) / 60) * hourH
        return max(36, min(max(minimumEventHeight, durationHeight), canvasHeight(pixelsPerHour: pixelsPerHour) - y))
    }

    /// Top of the 28pt duration edge, in canvas coordinates.
    static func durationHandleTop(
        duration: Double,
        y: CGFloat,
        pixelsPerHour: Double,
        handle: CGFloat = 28
    ) -> CGFloat {
        y + blockFrameHeight(duration: duration, y: y, pixelsPerHour: pixelsPerHour) - handle
    }

    /// Timed card in canvas space (6pt leading inset, matching DayColumnView).
    static func blockFrame(event: PlacedEvent, columnWidth: CGFloat, leading: CGFloat = 6) -> CGRect {
        CGRect(
            x: leading,
            y: event.y,
            width: max(0, columnWidth - leading * 2),
            height: max(event.height, 36)
        )
    }

    /// Hour-grid SpatialTap must ignore only this rect — Y-only matched any event at
    /// that hour, and full-canvas card wrappers swallowed empty-hour taps (`d94cb61`).
    /// Bottom/side slop matches the visible capsule hit slop.
    static func blockContains(location: CGPoint, event: PlacedEvent, columnWidth: CGFloat) -> Bool {
        let frame = blockFrame(event: event, columnWidth: columnWidth)
        let hittable = CGRect(
            x: frame.minX - 6,
            y: frame.minY,
            width: frame.width + 12,
            height: frame.height + 10
        )
        return hittable.contains(location)
    }

    /// Bottom 16pt of a timed card in the hour scroller's **content** space.
    static func durationCapsuleRect(
        columnIndex: Int,
        columnWidth: CGFloat,
        event: PlacedEvent,
        handle: CGFloat = 16
    ) -> CGRect {
        let height = max(event.height, 36)
        return CGRect(
            x: CGFloat(columnIndex) * columnWidth + 6,
            y: event.y + height - handle,
            width: max(0, columnWidth - 12),
            height: handle
        )
    }

    /// Convert a location on the hour UIScrollView into **content** coordinates.
    ///
    /// UIScrollView may keep `bounds.origin` at zero (SwiftUI) or equal to
    /// `contentOffset` (classic). Subtracting `bounds.origin` avoids counting
    /// the offset twice — a double-count misses the visible capsule and the
    /// hour grid steals the pan (`cafff4f`).
    static func hourContentPoint(
        locationInScroll: CGPoint,
        contentOffset: CGPoint,
        boundsOrigin: CGPoint,
        adjustedContentInset: UIEdgeInsets = .zero
    ) -> CGPoint {
        CGPoint(
            x: locationInScroll.x + contentOffset.x - adjustedContentInset.left - boundsOrigin.x,
            y: locationInScroll.y + contentOffset.y - adjustedContentInset.top - boundsOrigin.y
        )
    }

    /// Convert a touch on the hour UIScrollView into content coordinates.
    /// Always use offset/bounds math — a SwiftUI content subview is often
    /// viewport-sized, so `location(in: canvas)` misses the painted capsule
    /// (`e2fba41`).
    static func hourContentPoint(touch: UITouch, in scroll: UIScrollView) -> CGPoint {
        hourContentPoint(
            locationInScroll: touch.location(in: scroll),
            contentOffset: scroll.contentOffset,
            boundsOrigin: scroll.bounds.origin,
            adjustedContentInset: scroll.adjustedContentInset
        )
    }

    /// Bottom `handle` band of a UIKit view in window space. Zero-size
    /// representables fall back to the host; a full-card host is clipped to
    /// the bottom 16pt so a title tap still opens Details.
    static func durationHandleWindowRect(
        handleInWindow: CGRect,
        hostInWindow: CGRect,
        handleHeight: CGFloat = 16
    ) -> CGRect {
        var rect = handleInWindow
        if rect.width < 2 || rect.height < 2 {
            rect = hostInWindow
        }
        if rect.height > handleHeight + 8 {
            rect = CGRect(
                x: rect.minX,
                y: rect.maxY - handleHeight,
                width: rect.width,
                height: handleHeight
            )
        }
        return rect
    }

    /// Capsule-only hit. Card-body points must return false so Details still opens.
    static func touchHitsCapsule(
        _ point: CGPoint,
        capsule: CGRect,
        slopX: CGFloat = 6,
        slopY: CGFloat = 4
    ) -> Bool {
        guard !capsule.isNull, !capsule.isInfinite, capsule.width > 1, capsule.height > 1 else {
            return false
        }
        return capsule.insetBy(dx: -slopX, dy: -slopY).contains(point)
    }

    static func scrollTargetHour(now: Date = .now, calendar: Calendar = .current) -> Int {
        let hour = calendar.component(.hour, from: now)
        return min(max(hour - 1, startHour), max(endHour - 4, startHour))
    }

    static func y(fromMinutes minutes: Int, pixelsPerHour: Double) -> CGFloat {
        let clamped = min(max(minutes, 0), endHour * 60 - 1)
        return CGFloat(clamped) / 60 * hourHeight(pixelsPerHour: pixelsPerHour)
    }

    /// Round to the nearest snap, matching the web `snap()` helper.
    static func minutes(atY y: CGFloat, pixelsPerHour: Double, snap: Int = 15) -> Int {
        let hourH = hourHeight(pixelsPerHour: pixelsPerHour)
        let raw = Double(y) / Double(hourH) * 60
        let step = Double(max(snap, 1))
        let snapped = (raw / step).rounded() * step
        let maxMinutes = Double(endHour * 60 - Int(step))
        return Int(min(max(snapped, 0), maxMinutes))
    }

    static func clock(fromMinutes minutes: Int) -> String {
        let bounded = min(max(minutes, 0), endHour * 60 - 1)
        return String(format: "%02d:%02d", bounded / 60, bounded % 60)
    }

    static func hourLabel(_ hour: Int) -> String {
        "\(hour)"
    }

    static func nowY(now: Date = .now, calendar: Calendar = .current, pixelsPerHour: Double) -> CGFloat {
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return CGFloat(minutes) / 60 * hourHeight(pixelsPerHour: pixelsPerHour)
    }

    /// Web `jumpToToday` vertical offset: now minus 48pt headroom.
    static func nowScrollY(now: Date = .now, calendar: Calendar = .current, pixelsPerHour: Double, headroom: CGFloat = 48) -> CGFloat {
        max(0, nowY(now: now, calendar: calendar, pixelsPerHour: pixelsPerHour) - headroom)
    }

    /// Day-strip X and hour-scroller Y are independent. Never write `x` onto the
    /// vertical hour UIScrollView (`b956880` shoved chrome to x≈3070).
    static func timedContentOffset(
        todayIndex: Int,
        columnWidth: CGFloat,
        now: Date = .now,
        calendar: Calendar = .current,
        pixelsPerHour: Double,
        headroom: CGFloat = 48
    ) -> CGPoint {
        CGPoint(
            x: max(0, CGFloat(todayIndex) * columnWidth),
            y: nowScrollY(now: now, calendar: calendar, pixelsPerHour: pixelsPerHour, headroom: headroom)
        )
    }

    /// Web `DurationAdjuster.updateDuration`: minutes += deltaY / (pixelsPerHour / 60).
    static func previewDuration(start: Double, deltaY: CGFloat, pixelsPerHour: Double) -> Double {
        let minutesPerPoint = 60 / Double(hourHeight(pixelsPerHour: pixelsPerHour))
        let minDuration = Double(minimumEventHeight) * minutesPerPoint
        return max(minDuration, start + Double(deltaY) * minutesPerPoint)
    }

    static func snapDuration(_ duration: Double, snap: Int) -> Double {
        let step = Double(max(snap, 1))
        return max(step, (duration / step).rounded() * step)
    }

    static func dayWindow(
        around now: Date = .now,
        past: Int,
        future: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        let start = calendar.startOfDay(for: now)
        let origin = calendar.date(byAdding: .day, value: -past, to: start) ?? start
        return (0..<(past + future + 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: origin) }
    }
}
