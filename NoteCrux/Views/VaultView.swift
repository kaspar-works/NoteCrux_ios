import SwiftData
import SwiftUI
import LocalAuthentication

struct VaultView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query(sort: \MeetingFolder.name) private var folders: [MeetingFolder]
    @AppStorage("requireBiometrics") private var requireBiometrics = true
    @State private var searchText = ""
    @State private var selectedTag = "All"
    @State private var selectedFolderID: UUID?
    @State private var dateFilter: MeetingDateFilter = .all
    @State private var importanceFilter: MeetingImportanceFilter = .all
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isUnlocked = false
    @State private var authenticationMessage: String?

    private let search = LocalMeetingSearch()

    private var availableTags: [String] {
        let tags = Set(meetings.flatMap(\.tags))
        return ["All"] + tags.sorted()
    }

    private var filteredMeetings: [Meeting] {
        return meetings.filter { meeting in
            let matchesSearch = search.matches(meeting, query: searchText)
            let matchesTag = selectedTag == "All" || meeting.tags.contains(selectedTag)
            let matchesFolder = selectedFolderID == nil || meeting.folder?.id == selectedFolderID
            let matchesDate = dateFilter.matches(meeting.createdAt)
            let matchesImportance = importanceFilter.matches(meeting.importance)

            return matchesSearch && matchesTag && matchesFolder && matchesDate && matchesImportance
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBackground.ignoresSafeArea()

                if requireBiometrics && !isUnlocked {
                    LockedVaultView(message: authenticationMessage) {
                        authenticate()
                    }
                } else {
                    VStack(spacing: NCSpacing.md) {
                        VaultFiltersView(
                            folders: folders,
                            availableTags: availableTags,
                            selectedFolderID: $selectedFolderID,
                            selectedTag: $selectedTag,
                            dateFilter: $dateFilter,
                            importanceFilter: $importanceFilter,
                            createFolder: { isCreatingFolder = true }
                        )
                        .padding(.horizontal, NCSpacing.lg)

                        if filteredMeetings.isEmpty {
                            ContentUnavailableView(
                                meetings.isEmpty ? "No meetings saved" : "No matching meetings",
                                systemImage: "lock.doc",
                                description: Text(meetings.isEmpty ? "Recorded meetings will appear here after local processing." : "Try a different keyword, folder, tag, date, or importance filter.")
                            )
                        } else {
                            List(filteredMeetings) { meeting in
                                NavigationLink {
                                    InsightView(meeting: meeting)
                                } label: {
                                    MeetingRow(meeting: meeting)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(meeting)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Vault")
            .searchable(text: $searchText, prompt: "Search transcripts, notes, tasks")
            .alert("New Folder", isPresented: $isCreatingFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create", action: createFolder)
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
            } message: {
                Text("Group meetings by client, project, or topic.")
            }
        }
        .task {
            if requireBiometrics && !isUnlocked {
                authenticate()
            }
        }
    }

    private func delete(_ meeting: Meeting) {
        modelContext.delete(meeting)
        try? modelContext.save()
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        modelContext.insert(MeetingFolder(name: name))
        try? modelContext.save()
        newFolderName = ""
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            authenticationMessage = error?.localizedDescription ?? "Biometric authentication is not available on this device."
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock your private meeting vault."
        ) { success, error in
            Task { @MainActor in
                isUnlocked = success
                authenticationMessage = success ? nil : error?.localizedDescription
            }
        }
    }
}

private struct VaultFiltersView: View {
    let folders: [MeetingFolder]
    let availableTags: [String]
    @Binding var selectedFolderID: UUID?
    @Binding var selectedTag: String
    @Binding var dateFilter: MeetingDateFilter
    @Binding var importanceFilter: MeetingImportanceFilter
    let createFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NCSpacing.sm) {
                    FilterChip(title: "All Folders", isSelected: selectedFolderID == nil) {
                        selectedFolderID = nil
                    }

                    ForEach(folders) { folder in
                        FilterChip(title: folder.name, isSelected: selectedFolderID == folder.id) {
                            selectedFolderID = folder.id
                        }
                    }

                    Button(action: createFolder) {
                        Label("Folder", systemImage: "plus")
                            .font(.ncCaption1)
                            .padding(.horizontal, NCSpacing.md)
                            .padding(.vertical, NCSpacing.sm)
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Picker("Tag", selection: $selectedTag) {
                    ForEach(availableTags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }

                Picker("Date", selection: $dateFilter) {
                    ForEach(MeetingDateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }

                Picker("Importance", selection: $importanceFilter) {
                    ForEach(MeetingImportanceFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            }
            .pickerStyle(.menu)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ncCaption1)
                .padding(.horizontal, NCSpacing.md)
                .padding(.vertical, NCSpacing.sm)
                .foregroundStyle(isSelected ? .white : Color.ncSecondary)
                .background(isSelected ? Color.ncPurple : Color.ncPurple.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LockedVaultView: View {
    let message: String?
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: NCSpacing.xl) {
            Image(systemName: "faceid")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.ncPurple)

            Text("Vault Locked")
                .font(.ncTitle1)

            Text(message ?? "Use Face ID to open your private meeting archive.")
                .font(.ncBody)
                .foregroundStyle(Color.ncMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NCSpacing.xxxl)

            Button("Unlock Vault", action: unlock)
                .buttonStyle(.borderedProminent)
                .tint(Color.ncPurple)
        }
        .padding(NCSpacing.xxl)
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            HStack {
                Text(meeting.title)
                    .font(.ncHeadline)
                Spacer()
                Text(meeting.createdAt, style: .date)
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncMuted)
            }

            Text(meeting.summary.isEmpty ? "No summary available." : meeting.summary)
                .font(.ncBody)
                .foregroundStyle(Color.ncSecondary)
                .lineLimit(2)

            HStack(spacing: NCSpacing.md) {
                Label("\(meeting.actionItems.count)", systemImage: "checklist")
                Label(formatDuration(meeting.duration), systemImage: "timer")
                if let folderName = meeting.folder?.name {
                    Label(folderName, systemImage: "folder")
                }
            }
            .font(.ncCaption1)
            .foregroundStyle(Color.ncMuted)

            if !meeting.tags.isEmpty {
                HStack(spacing: NCSpacing.sm) {
                    ForEach(meeting.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.ncCaption2)
                            .padding(.horizontal, NCSpacing.sm)
                            .padding(.vertical, NCSpacing.xs)
                            .background(Color.ncPurple.opacity(0.16), in: RoundedRectangle(cornerRadius: NCRadius.small))
                    }
                }
            }
        }
        .padding(.vertical, NCSpacing.sm)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
}

enum MeetingDateFilter: String, CaseIterable, Identifiable {
    case all = "Any Date"
    case today = "Today"
    case week = "This Week"
    case month = "This Month"

    var id: String { rawValue }

    func matches(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(date)
        case .week:
            return calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
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
        case .all:
            return true
        case .important:
            return importance == .important || importance == .critical
        case .critical:
            return importance == .critical
        }
    }
}
