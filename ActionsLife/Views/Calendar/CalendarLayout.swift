import CoreGraphics
import Foundation

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
