import Foundation
import WidgetKit

enum WidgetDataSync {
    private static let appGroupID = "group.com.codergautamyt.notecrux"
    private static let todaysMeetingCountKey = "widget.todaysMeetingCount"
    private static let pendingTasksCountKey = "widget.pendingTasksCount"
    private static let nextEventTitleKey = "widget.nextEventTitle"
    private static let nextEventStartKey = "widget.nextEventStart"
    private static let lastUpdatedKey = "widget.lastUpdated"

    static func update(
        todaysMeetingCount: Int,
        pendingTasksCount: Int,
        nextEventTitle: String?,
        nextEventStart: Date?
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(todaysMeetingCount, forKey: todaysMeetingCountKey)
        defaults.set(pendingTasksCount, forKey: pendingTasksCountKey)
        defaults.set(nextEventTitle, forKey: nextEventTitleKey)
        defaults.set(nextEventStart, forKey: nextEventStartKey)
        defaults.set(Date(), forKey: lastUpdatedKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "NoteCruxTodayWidget")
    }
}
