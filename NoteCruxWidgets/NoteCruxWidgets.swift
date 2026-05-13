import WidgetKit
import SwiftUI

enum NoteCruxWidgetData {
    static let appGroupID = "group.com.codergautamyt.notecrux"

    static let todaysMeetingCountKey = "widget.todaysMeetingCount"
    static let pendingTasksCountKey = "widget.pendingTasksCount"
    static let nextEventTitleKey = "widget.nextEventTitle"
    static let nextEventStartKey = "widget.nextEventStart"
    static let lastUpdatedKey = "widget.lastUpdated"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let todaysMeetingCount: Int
    let pendingTasksCount: Int
    let nextEventTitle: String?
    let nextEventStart: Date?

    static let placeholder = TodayEntry(
        date: Date(),
        todaysMeetingCount: 3,
        pendingTasksCount: 4,
        nextEventTitle: "Dialysis visit",
        nextEventStart: Date().addingTimeInterval(45 * 60)
    )
}

struct TodayTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = readEntry()
        let refreshAt = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refreshAt)))
    }

    private func readEntry() -> TodayEntry {
        let defaults = NoteCruxWidgetData.defaults
        let nextEventStart = (defaults?.object(forKey: NoteCruxWidgetData.nextEventStartKey) as? Date)
        return TodayEntry(
            date: Date(),
            todaysMeetingCount: defaults?.integer(forKey: NoteCruxWidgetData.todaysMeetingCountKey) ?? 0,
            pendingTasksCount: defaults?.integer(forKey: NoteCruxWidgetData.pendingTasksCountKey) ?? 0,
            nextEventTitle: defaults?.string(forKey: NoteCruxWidgetData.nextEventTitleKey),
            nextEventStart: nextEventStart
        )
    }
}

struct NoteCruxWidgets: Widget {
    let kind: String = "NoteCruxTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(Color(red: 0.98, green: 0.97, blue: 1.0), for: .widget)
        }
        .configurationDisplayName("Today at a Glance")
        .description("Your meetings, tasks, and next event.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private let accent = Color(red: 0.48, green: 0.38, blue: 0.93)

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(entry.todaysMeetingCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(entry.todaysMeetingCount == 1 ? "meeting" : "meetings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                Text("\(entry.pendingTasksCount) task\(entry.pendingTasksCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.todaysMeetingCount)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(entry.todaysMeetingCount == 1 ? "meeting" : "meetings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                    Text("\(entry.pendingTasksCount) task\(entry.pendingTasksCount == 1 ? "" : "s") pending")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .overlay(Color.secondary.opacity(0.3))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                    Text("NEXT UP")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }

                if let title = entry.nextEventTitle, let start = entry.nextEventStart {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(start, style: .time)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)

                    Text(start, style: .relative)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No upcoming events")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Small", as: .systemSmall) {
    NoteCruxWidgets()
} timeline: {
    TodayEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    NoteCruxWidgets()
} timeline: {
    TodayEntry.placeholder
}
