import Foundation

@MainActor
@Observable
final class AppNavigation {
    var selectedDay = Calendar.current.startOfDay(for: .now)
    var selectedTaskID: String?

    func open(taskID: String, dayISO: String) {
        if let day = DateISO.date(fromDayISO: dayISO) {
            selectedDay = Calendar.current.startOfDay(for: day)
        }
        selectedTaskID = taskID
    }
}
