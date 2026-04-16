import SwiftData
import SwiftUI
import LocalAuthentication

struct VaultView: View {
    @Environment(\.colorScheme) private var colorScheme
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
                DeepPocketTheme.background(for: colorScheme).ignoresSafeArea()

                if requireBiometrics && !isUnlocked {
                    LockedVaultView(message: authenticationMessage) {
                        authenticate()
                    }
                } else {
                    VStack(spacing: 10) {
                        VaultFiltersView(
                            folders: folders,
                            availableTags: availableTags,
                            selectedFolderID: $selectedFolderID,
                            selectedTag: $selectedTag,
                            dateFilter: $dateFilter,
                            importanceFilter: $importanceFilter,
                            createFolder: { isCreatingFolder = true }
                        )
                        .padding(.horizontal)

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
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
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
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .black : .primary)
                .background(isSelected ? Color.green : Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct LockedVaultView: View {
    let message: String?
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "faceid")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.green)

            Text("Vault Locked")
                .font(.title.bold())

            Text(message ?? "Use Face ID to open your private meeting archive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button("Unlock Vault", action: unlock)
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding(24)
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(meeting.title)
                    .font(.headline)
                Spacer()
                Text(meeting.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(meeting.summary.isEmpty ? "No summary available." : meeting.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label("\(meeting.actionItems.count)", systemImage: "checklist")
                Label(formatDuration(meeting.duration), systemImage: "timer")
                if let folderName = meeting.folder?.name {
                    Label(folderName, systemImage: "folder")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !meeting.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(meeting.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(.vertical, 6)
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
