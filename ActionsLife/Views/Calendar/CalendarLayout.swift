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

    /// Timed card in canvas space (6pt leading inset). `BlockFrameCardLayout`
    /// places a card-sized child at this origin so `hitTest` matches paint.
    static func blockFrame(event: PlacedEvent, columnWidth: CGFloat, leading: CGFloat = 6) -> CGRect {
        CGRect(
            x: leading,
            y: event.y,
            width: max(0, columnWidth - leading * 2),
            height: max(event.height, 36)
        )
    }

    /// Accessibility IDs on the painted timed card / 16pt capsule. Scroller
    /// `hitTest` walks these. Spacer / canvas hosts must not carry them.
    static let timedCardAccessibilityPrefix = "calendar.timed."
    static let timedCapsuleAccessibilityPrefix = "calendar.capsule."

    static func timedCardAccessibilityID(_ taskID: String) -> String {
        timedCardAccessibilityPrefix + taskID
    }

    static func timedCapsuleAccessibilityID(_ taskID: String) -> String {
        timedCapsuleAccessibilityPrefix + taskID
    }

    /// `task.id` stamped on the painted card / capsule UIView.
    static func taskID(fromPaintedView view: UIView?) -> String? {
        var current = view
        while let node = current {
            if node is UIScrollView { break }
            if let id = node.accessibilityIdentifier, !id.isEmpty {
                if id.hasPrefix(timedCapsuleAccessibilityPrefix) {
                    let taskID = String(id.dropFirst(timedCapsuleAccessibilityPrefix.count))
                    if !taskID.isEmpty { return taskID }
                }
                if id.hasPrefix(timedCardAccessibilityPrefix) {
                    let taskID = String(id.dropFirst(timedCardAccessibilityPrefix.count))
                    if !taskID.isEmpty { return taskID }
                }
            }
            if let value = node.accessibilityValue, !value.isEmpty {
                return value
            }
            current = node.superview
        }
        return nil
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

    /// Hour-canvas view `UIView.convert` should land on: the subview whose
    /// bounds match `contentSize` (the HStack of day columns). Skip
    /// indicators. If nothing matches, the scroll view itself — then
    /// `blockFramePoint` applies `contentOffset`.
    static func hourCanvasContentView(in scroll: UIScrollView) -> UIView {
        let target = scroll.contentSize
        var best: UIView = scroll
        var bestScore = CGFloat.greatestFiniteMagnitude
        for sub in scroll.subviews {
            let name = String(describing: type(of: sub))
            if name.contains("Indicator") || name.contains("UIImageView") { continue }
            if sub.bounds.width < 2 || sub.bounds.height < 2 { continue }
            let score = abs(sub.bounds.width - target.width) + abs(sub.bounds.height - target.height)
            if score < bestScore {
                bestScore = score
                best = sub
            }
        }
        return best
    }

    /// Convert a scroller location with `UIView.convert` into `blockFrame`
    /// space (hour 0 at y = 0). Sticky all-day `headerHeight` and
    /// `contentOffset` are the two terms that differ from scroll-view
    /// bounds. Do not GeometryReader-fallback (`54090ed` still missed).
    static func blockFramePoint(
        locationInScroll: CGPoint,
        scroll: UIScrollView,
        headerHeight: CGFloat
    ) -> CGPoint {
        let canvas = hourCanvasContentView(in: scroll)
        let converted = scroll.convert(locationInScroll, to: canvas)
        return blockFramePoint(
            converted: converted,
            contentOffset: scroll.contentOffset,
            boundsOrigin: scroll.bounds.origin,
            headerHeight: headerHeight,
            canvasSize: canvas.bounds.size,
            contentSize: scroll.contentSize,
            convertedFromScrollView: canvas === scroll,
            canvasFrameOrigin: canvas === scroll ? .zero : canvas.frame.origin,
            adjustedContentInset: scroll.adjustedContentInset,
            horizontalContentOffset: enclosingHorizontalContentOffset(of: scroll)
        )
    }

    static func blockFramePoint(touch: UITouch, in scroll: UIScrollView, headerHeight: CGFloat) -> CGPoint {
        blockFramePoint(
            locationInScroll: touch.location(in: scroll),
            scroll: scroll,
            headerHeight: headerHeight
        )
    }

    /// Pure mapping used by tests and by the UIView.convert wrapper.
    ///
    /// - Convert onto a **content-sized** canvas already includes
    ///   `contentOffset` when that canvas is shifted by `-offset` or the
    ///   scroll view's `bounds.origin` equals `contentOffset`.
    /// - Convert onto the scroll view / a viewport host still needs
    ///   `contentOffset` so hour 7 paint matches `blockFrame.y`.
    /// - If that canvas still includes the sticky all-day row, subtract
    ///   `headerHeight`.
    /// - Nested 1-axis: a viewport-wide hour canvas must add the parent
    ///   day-strip X or today's column is index 0 (`e2fba41`).
    static func blockFramePoint(
        converted: CGPoint,
        contentOffset: CGPoint,
        boundsOrigin: CGPoint,
        headerHeight: CGFloat,
        canvasSize: CGSize,
        contentSize: CGSize,
        convertedFromScrollView: Bool,
        canvasFrameOrigin: CGPoint = .zero,
        adjustedContentInset: UIEdgeInsets = .zero,
        horizontalContentOffset: CGFloat = 0
    ) -> CGPoint {
        var point = converted
        let coversY = canvasSize.height >= contentSize.height - 1
        let coversX = canvasSize.width >= contentSize.width - 1
        let needsOffsetY = convertedFromScrollView
            || !coversY
            || (abs(canvasFrameOrigin.y) < 0.5 && abs(contentOffset.y - boundsOrigin.y) > 0.5)
        let needsOffsetX = convertedFromScrollView
            || !coversX
            || (abs(canvasFrameOrigin.x) < 0.5 && abs(contentOffset.x - boundsOrigin.x) > 0.5)
        if needsOffsetY {
            point.y += contentOffset.y - boundsOrigin.y - adjustedContentInset.top
        }
        if needsOffsetX {
            point.x += contentOffset.x - boundsOrigin.x - adjustedContentInset.left
        }
        if headerHeight > 1, canvasSize.height >= contentSize.height + headerHeight - 1 {
            point.y -= headerHeight
        }
        if !coversX, canvasSize.width > 1, point.x <= canvasSize.width + 1 {
            point.x += horizontalContentOffset
        }
        return point
    }

    /// Convert a touch on the hour UIScrollView into content coordinates.
    /// Always use offset/bounds math — a SwiftUI content subview is often
    /// viewport-sized, so `location(in: canvas)` misses the painted capsule
    /// (`e2fba41`).
    ///
    /// The hour scroller sits inside a horizontal day strip. If its content is
    /// only viewport-wide, column X lives on the parent (`e2fba41` missed
    /// capsules at `todayIndex × columnWidth`). Full-width hour content already
    /// includes that X — do not add the parent offset twice.
    static func hourContentPoint(touch: UITouch, in scroll: UIScrollView) -> CGPoint {
        hourContentPoint(locationInScroll: touch.location(in: scroll), scroll: scroll)
    }

    static func hourContentPoint(locationInScroll: CGPoint, scroll: UIScrollView) -> CGPoint {
        hourContentPoint(
            locationInScroll: locationInScroll,
            contentOffset: scroll.contentOffset,
            boundsOrigin: scroll.bounds.origin,
            adjustedContentInset: scroll.adjustedContentInset,
            hourContentWidth: scroll.contentSize.width,
            hourBoundsWidth: scroll.bounds.width,
            horizontalContentOffset: enclosingHorizontalContentOffset(of: scroll)
        )
    }

    static func enclosingHorizontalContentOffset(of view: UIView) -> CGFloat {
        var current: UIView? = view.superview
        while let node = current {
            if let parent = node as? UIScrollView,
               parent.contentSize.width > parent.bounds.width + 1
            {
                return parent.contentOffset.x - parent.bounds.origin.x - parent.adjustedContentInset.left
            }
            current = node.superview
        }
        return 0
    }

    static func hourContentPoint(
        locationInScroll: CGPoint,
        contentOffset: CGPoint,
        boundsOrigin: CGPoint,
        adjustedContentInset: UIEdgeInsets = .zero,
        hourContentWidth: CGFloat,
        hourBoundsWidth: CGFloat,
        horizontalContentOffset: CGFloat
    ) -> CGPoint {
        var point = hourContentPoint(
            locationInScroll: locationInScroll,
            contentOffset: contentOffset,
            boundsOrigin: boundsOrigin,
            adjustedContentInset: adjustedContentInset
        )
        if hourContentWidth <= hourBoundsWidth + 1, locationInScroll.x <= hourBoundsWidth + 1 {
            point.x += horizontalContentOffset
        }
        return point
    }

    /// Painted 16pt capsule in hour-scroller content space, plus the task
    /// `setDuration` should write when that capsule is under the finger.
    struct DurationCapsuleTarget: Equatable {
        var taskID: String
        var duration: Double
        var rect: CGRect
    }

    static func hitDurationCapsule(
        contentPoint: CGPoint,
        capsules: [DurationCapsuleTarget]
    ) -> DurationCapsuleTarget? {
        capsules.first { touchHitsCapsule(contentPoint, capsule: $0.rect) }
    }

    /// One day column in hour-scroller content space (index × columnWidth).
    struct HourCanvasColumn: Equatable {
        var dayISO: String
        var events: [PlacedEvent]
    }

    /// Live timed columns from the store. The scroller coordinator must not
    /// keep a stale struct copy — `54090ed` then classified a title tap on
    /// the new hour-7 card as empty hour.
    static func hourCanvasColumns(
        dayISOs: [String],
        tasksOnDay: (String) -> [TaskSnapshot],
        pixelsPerHour: Double,
        previewTaskID: String? = nil,
        previewDuration: Double? = nil
    ) -> [HourCanvasColumn] {
        dayISOs.map { iso in
            var timed = split(tasks: tasksOnDay(iso)).timed
            var originals: [String: Double] = [:]
            for task in timed {
                originals[task.id] = task.duration
            }
            if let previewTaskID, let previewDuration,
               let slot = timed.firstIndex(where: { $0.id == previewTaskID })
            {
                timed[slot].duration = previewDuration
            }
            let events = placeTimed(timed, pixelsPerHour: pixelsPerHour).map { event -> PlacedEvent in
                var event = event
                event.task.duration = originals[event.task.id] ?? event.task.duration
                return event
            }
            return HourCanvasColumn(dayISO: iso, events: events)
        }
    }

    /// Hit-test the hour canvas in **blockFrame** coordinates. Empty hours are
    /// always timed (never all-day). Capsule wins over the card body.
    enum HourCanvasHit: Equatable {
        case capsule(DurationCapsuleTarget)
        case blockBody(taskID: String)
        case emptyHour(dayISO: String, minutes: Int)
    }

    static func hourCanvasHit(
        contentPoint: CGPoint,
        columns: [HourCanvasColumn],
        columnWidth: CGFloat,
        pixelsPerHour: Double,
        snap: Int
    ) -> HourCanvasHit? {
        guard columnWidth > 1, !columns.isEmpty else { return nil }
        let index = Int(floor(max(contentPoint.x, 0) / columnWidth))
        guard columns.indices.contains(index) else { return nil }
        let column = columns[index]
        let local = CGPoint(
            x: contentPoint.x - CGFloat(index) * columnWidth,
            y: contentPoint.y
        )
        for event in column.events {
            let capsule = durationCapsuleRect(columnIndex: 0, columnWidth: columnWidth, event: event)
            if touchHitsCapsule(local, capsule: capsule) {
                return .capsule(
                    DurationCapsuleTarget(
                        taskID: event.task.id,
                        duration: event.task.duration,
                        rect: durationCapsuleRect(
                            columnIndex: index,
                            columnWidth: columnWidth,
                            event: event
                        )
                    )
                )
            }
        }
        for event in column.events {
            if blockContains(location: local, event: event, columnWidth: columnWidth) {
                return .blockBody(taskID: event.task.id)
            }
        }
        return .emptyHour(
            dayISO: column.dayISO,
            minutes: minutes(atY: local.y, pixelsPerHour: pixelsPerHour, snap: snap)
        )
    }

    /// `UIScrollView.hitTest` / content-view `hitTest` at the scroller point.
    /// Nil and hour-grid views stay empty-hour create.
    static func hourScrollHitView(in scroll: UIScrollView, locationInScroll: CGPoint) -> UIView? {
        let canvas = hourCanvasContentView(in: scroll)
        if canvas !== scroll {
            let point = scroll.convert(locationInScroll, to: canvas)
            if let hit = canvas.hitTest(point, with: nil) {
                return hit
            }
        }
        return scroll.hitTest(locationInScroll, with: nil)
    }

    enum PaintedCardHit: Equatable {
        case capsule(taskID: String)
        case blockBody(taskID: String)
    }

    /// Divert only when `hitTest` landed on the **painted card** (or its 16pt
    /// capsule). Canvas-height hosts and hour-0 spacers are not cards
    /// (`adce52c` / `TimedCardLayout.place`).
    static func paintedCardHit(
        from view: UIView?,
        locationInScroll: CGPoint,
        in scroll: UIScrollView
    ) -> PaintedCardHit? {
        var current = view
        while let node = current {
            if node is UIScrollView { break }
            if node.bounds.width < 2 || node.bounds.height < 2 {
                current = node.superview
                continue
            }
            if isHourCanvasHost(node, scroll: scroll) { break }
            if !isPaintedCardSized(node, scroll: scroll) { break }
            let local = scroll.convert(locationInScroll, to: node)
            guard node.bounds.insetBy(dx: -1, dy: -1).contains(local) else {
                current = node.superview
                continue
            }
            if let id = node.accessibilityIdentifier, !id.isEmpty {
                if id.hasPrefix(timedCapsuleAccessibilityPrefix) {
                    let taskID = String(id.dropFirst(timedCapsuleAccessibilityPrefix.count))
                    if !taskID.isEmpty { return .capsule(taskID: taskID) }
                }
                if id.hasPrefix(timedCardAccessibilityPrefix) {
                    let taskID = String(id.dropFirst(timedCardAccessibilityPrefix.count))
                    if !taskID.isEmpty {
                        // Card-local bottom 16pt (`94e965c`). Convert-to-scroll
                        // missed the painted capsule so the pan never claimed
                        // the touch and hours scrolled (`b52d8de`).
                        if local.y >= node.bounds.height - 16 - 0.5 {
                            return .capsule(taskID: taskID)
                        }
                        return .blockBody(taskID: taskID)
                    }
                }
            }
            current = node.superview
        }
        return nil
    }

    /// Full-column / viewport views that swallowed empty-hour create.
    static func isHourCanvasHost(_ view: UIView, scroll: UIScrollView) -> Bool {
        let height = view.bounds.height
        let width = view.bounds.width
        if scroll.contentSize.height > 8, height >= scroll.contentSize.height - 8 {
            return true
        }
        if scroll.bounds.height > 8,
           height >= scroll.bounds.height - 8,
           width >= min(scroll.bounds.width, max(scroll.contentSize.width, 1)) - 8
        {
            return true
        }
        return false
    }

    /// Card body (~36pt+) or 16pt capsule — not a spacer from hour 0.
    static func isPaintedCardSized(_ view: UIView, scroll: UIScrollView) -> Bool {
        let height = view.bounds.height
        guard height >= 12, view.bounds.width >= 32 else { return false }
        if isHourCanvasHost(view, scroll: scroll) { return false }
        if scroll.bounds.height > 8, height >= scroll.bounds.height - 8 { return false }
        if scroll.contentSize.height > 8, height >= scroll.contentSize.height - 8 { return false }
        return true
    }

    /// The painted `calendar.timed.*` card UIView under a scroller point.
    /// Does not use `hitTest` (the 16pt capsule overlay is not this view).
    /// Title / empty-hour dispatch still uses `paintedCardHit` / `hourCanvasHit`.
    static func paintedTimedCard(in scroll: UIScrollView, locationInScroll: CGPoint) -> UIView? {
        var match: UIView?
        var stack: [UIView] = [scroll]
        while let view = stack.popLast() {
            if view !== scroll,
               let id = view.accessibilityIdentifier,
               id.hasPrefix(timedCardAccessibilityPrefix),
               !isHourCanvasHost(view, scroll: scroll),
               isPaintedCardSized(view, scroll: scroll)
            {
                let local = scroll.convert(locationInScroll, to: view)
                if view.bounds.insetBy(dx: -1, dy: -1).contains(local) {
                    // Prefer the card (~39pt), not the StaticText title
                    // (`28ee931` `(87.3, 319.3, 122.7, 18)` is Details).
                    if match == nil || view.bounds.height > match!.bounds.height {
                        match = view
                    }
                }
            }
            stack.append(contentsOf: view.subviews)
        }
        return match
    }

    /// Bottom 16pt of the painted card in the scroller's space (`94e965c`
    /// a11y card `(50, 280.3, 168, 39.3)` → capsule y≈303.6–319.6).
    static func paintedCapsuleBand(of card: UIView, in scroll: UIScrollView) -> CGRect {
        let rect = card.convert(card.bounds, to: scroll)
        return CGRect(
            x: rect.minX,
            y: rect.maxY - 16,
            width: rect.width,
            height: 16
        )
    }

    static func touchHitsPaintedCapsule(
        locationInScroll: CGPoint,
        card: UIView,
        in scroll: UIScrollView
    ) -> Bool {
        let local = scroll.convert(locationInScroll, to: card)
        guard card.bounds.insetBy(dx: -1, dy: -1).contains(local) else { return false }
        return local.y >= card.bounds.height - 16 - 0.5
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

    /// Capsule pan window `location.y` delta → minutes added to the start
    /// instant (the event’s end). Hour height is `max(36, pixelsPerHour)`.
    /// Web `DurationAdjuster.updateDuration`: minutes += deltaY / (pxPerHour / 60).
    static func durationFromLocationDelta(
        start: Double,
        locationDeltaY: CGFloat,
        pixelsPerHour: Double
    ) -> Double {
        previewDuration(start: start, deltaY: locationDeltaY, pixelsPerHour: pixelsPerHour)
    }

    /// Capsule pan `translation.y` → new duration (block end instant).
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
