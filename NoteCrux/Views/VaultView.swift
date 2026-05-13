import SwiftData
import SwiftUI

struct VaultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @State private var searchText = ""
    @State private var selectedTag = "All"
    @State private var dateFilter: MeetingDateFilter = .all
    @State private var showDeleteAllConfirmation = false
    @State private var meetingToDelete: Meeting?
    @State private var meetingToDeleteTitle = ""

    private let search = LocalMeetingSearch()

    private var activeMeetings: [Meeting] {
        meetings.filter { !$0.isDeleted }
    }

    private var availableTags: [String] {
        let tags = Set(activeMeetings.flatMap(\.tags))
        return ["All"] + tags.sorted()
    }

    private var filteredMeetings: [Meeting] {
        activeMeetings.filter { meeting in
            let matchesSearch = searchText.isEmpty || search.matches(meeting, query: searchText)
            let matchesTag = selectedTag == "All" || meeting.tags.contains(selectedTag)
            let matchesDate = dateFilter.matches(meeting.createdAt)
            return matchesSearch && matchesTag && matchesDate
        }
    }

    private var groupedMeetings: [(String, [Meeting])] {
        let grouped = Dictionary(grouping: filteredMeetings) { meeting in
            meeting.createdAt.sectionHeader
        }
        return grouped.sorted { $0.value[0].createdAt > $1.value[0].createdAt }
    }

    var body: some View {
        ZStack {
            Color.ncBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: NCSpacing.md) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.ncMuted)
                        }

                        Spacer()

                        Text("All Meetings")
                            .font(.ncHeadline)
                            .foregroundStyle(Color.ncInk)

                        Spacer()

                        if !activeMeetings.isEmpty {
                            Menu {
                                Button(role: .destructive) {
                                    showDeleteAllConfirmation = true
                                } label: {
                                    Label("Delete All", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.ncMuted)
                            }
                        } else {
                            Color.clear.frame(width: 18, height: 18)
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg)
                    .padding(.top, NCSpacing.md)

                    // Search
                    HStack(spacing: NCSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ncMuted)
                        TextField("Search meetings…", text: $searchText)
                            .font(.ncCallout)
                            .foregroundStyle(Color.ncInk)
                    }
                    .padding(.horizontal, NCSpacing.md)
                    .padding(.vertical, NCSpacing.sm + 2)
                    .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                    .padding(.horizontal, NCSpacing.lg)

                    // Filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NCSpacing.sm) {
                            ForEach(availableTags, id: \.self) { tag in
                                VaultFilterChip(title: tag, isSelected: selectedTag == tag) {
                                    selectedTag = tag
                                }
                            }

                            Divider().frame(height: 20)

                            ForEach(MeetingDateFilter.allCases) { filter in
                                VaultFilterChip(title: filter.rawValue, isSelected: dateFilter == filter) {
                                    dateFilter = filter
                                }
                            }
                        }
                        .padding(.horizontal, NCSpacing.lg)
                    }

                    // Count
                    HStack {
                        Text("\(filteredMeetings.count) meeting\(filteredMeetings.count == 1 ? "" : "s")")
                            .font(.ncCaption1.weight(.medium))
                            .foregroundStyle(Color.ncMuted)
                        Spacer()
                    }
                    .padding(.horizontal, NCSpacing.lg)
                }
                .padding(.bottom, NCSpacing.md)

                // Meeting list
                if filteredMeetings.isEmpty {
                    Spacer()
                    VStack(spacing: NCSpacing.lg) {
                        Image(systemName: activeMeetings.isEmpty ? "waveform.circle" : "magnifyingglass")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color.ncPurple.opacity(0.5))
                        Text(activeMeetings.isEmpty ? "No meetings yet" : "No matching meetings")
                            .font(.ncHeadline)
                            .foregroundStyle(Color.ncInk)
                        Text(activeMeetings.isEmpty ? "Recorded meetings will appear here." : "Try a different search or filter.")
                            .font(.ncFootnote)
                            .foregroundStyle(Color.ncMuted)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: NCSpacing.xl) {
                            ForEach(groupedMeetings, id: \.0) { section, sectionMeetings in
                                VStack(alignment: .leading, spacing: NCSpacing.md) {
                                    Text(section.uppercased())
                                        .font(.ncOverline)
                                        .tracking(1.0)
                                        .foregroundStyle(Color.ncMuted)
                                        .padding(.horizontal, NCSpacing.lg)

                                    ForEach(sectionMeetings) { meeting in
                                        NavigationLink {
                                            InsightView(meeting: meeting)
                                        } label: {
                                            VaultMeetingCard(meeting: meeting)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                meetingToDeleteTitle = meeting.title
                                                meetingToDelete = meeting
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .padding(.horizontal, NCSpacing.lg)
                                    }
                                }
                            }
                        }
                        .padding(.top, NCSpacing.sm)
                        .padding(.bottom, 94)
                    }
                    .refreshable {
                        // Force a re-render to refresh search/filter state
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete All Meetings?", isPresented: $showDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(activeMeetings.count) meetings. This cannot be undone.")
        }
        .alert("Delete Meeting?", isPresented: Binding(
            get: { meetingToDelete != nil },
            set: { if !$0 { meetingToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let meeting = meetingToDelete {
                    delete(meeting)
                    meetingToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { meetingToDelete = nil }
        } message: {
            Text("This will permanently delete \"\(meetingToDeleteTitle)\".")
        }
    }

    private func delete(_ meeting: Meeting) {
        modelContext.delete(meeting)
        try? modelContext.save()
    }

    private func deleteAll() {
        for meeting in meetings {
            modelContext.delete(meeting)
        }
        try? modelContext.save()
    }
}

// MARK: - Meeting Card

private struct VaultMeetingCard: View {
    let meeting: Meeting

    private var excerpt: String {
        let candidates = [meeting.quickRead, meeting.summary, meeting.highlights.first ?? ""]
        let text = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "No notes yet."
        return text.count > 120 ? String(text.prefix(117)) + "…" : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm + 2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: NCSpacing.xs) {
                    Text(meeting.title)
                        .font(.ncHeadline)
                        .foregroundStyle(Color.ncInk)
                        .lineLimit(1)

                    HStack(spacing: NCSpacing.sm) {
                        Text(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)

                        Text("•")
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)

                        Text(meeting.duration.vaultDuration)
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ncMuted)
                    .padding(.top, 4)
            }

            Text(excerpt)
                .font(.ncFootnote)
                .lineSpacing(2)
                .foregroundStyle(Color.ncSecondary)
                .lineLimit(2)

            HStack(spacing: NCSpacing.sm) {
                if !meeting.actionItems.isEmpty {
                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(meeting.actionItems.count)")
                            .font(.ncCaption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.ncPurple)
                    .padding(.horizontal, NCSpacing.sm)
                    .padding(.vertical, NCSpacing.xs)
                    .background(Color.ncPurple.opacity(0.10), in: Capsule())
                }

                ForEach(meeting.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.ncCaption2)
                        .foregroundStyle(Color.ncPurple)
                        .padding(.horizontal, NCSpacing.sm)
                        .padding(.vertical, NCSpacing.xs)
                        .background(Color.ncPurple.opacity(0.10), in: Capsule())
                }
            }
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.subtle)
    }
}

// MARK: - Filter Chip

private struct VaultFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ncCaption1.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Color.ncMuted)
                .padding(.horizontal, NCSpacing.md)
                .padding(.vertical, NCSpacing.sm)
                .background(isSelected ? Color.ncPurple : Color.ncSurface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color.ncDivider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date Helpers

private extension Date {
    var sectionHeader: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .weekOfYear) { return "This Week" }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .month) { return "This Month" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: self)
    }
}

private extension TimeInterval {
    var vaultDuration: String {
        let minutes = max(1, Int((self / 60).rounded()))
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes) min"
    }
}

// MARK: - Filters

enum MeetingDateFilter: String, CaseIterable, Identifiable {
    case all = "Any Date"
    case today = "Today"
    case week = "This Week"
    case month = "This Month"

    var id: String { rawValue }

    func matches(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all: return true
        case .today: return calendar.isDateInToday(date)
        case .week: return calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        case .month: return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
        }
    }
}

enum MeetingImportanceFilter: String, CaseIterable, Identifiable {
    case all = "Any Importance"
    case important = "Important"
    case critical = "Critical"

    var id: String { rawValue }

    func matches(_ importance: MeetingImportance) -> Bool {
        switch self {
        case .all: return true
        case .important: return importance == .important || importance == .critical
        case .critical: return importance == .critical
        }
    }
}
