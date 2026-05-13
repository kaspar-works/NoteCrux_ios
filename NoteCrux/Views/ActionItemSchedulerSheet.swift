import SwiftUI

/// Shown after a meeting is saved. Lists every extracted action item and
/// lets the user schedule each one as a calendar event. For each item we
/// scan the title+detail for a date/time reference (via NSDataDetector):
/// if we find one we pre-fill the picker; otherwise the picker defaults
/// to "tomorrow 9am" and the user can adjust.
struct ActionItemSchedulerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let actionItems: [MeetingActionItem]
    let meetingTitle: String

    @State private var suggestions: [ItemSuggestion] = []
    @State private var scheduledIDs: Set<UUID> = []
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NCSpacing.lg) {
                    header

                    if suggestions.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: NCSpacing.md) {
                            ForEach($suggestions) { $suggestion in
                                SchedulerRow(
                                    suggestion: $suggestion,
                                    isScheduled: scheduledIDs.contains(suggestion.itemID),
                                    onSchedule: { await schedule(suggestion) }
                                )
                            }
                        }
                    }
                }
                .padding(NCSpacing.lg)
            }
            .background(Color.ncBackground.ignoresSafeArea())
            .navigationTitle("Follow-ups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(Color.ncMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.ncPurple)
                }
            }
        }
        .task {
            await CalendarImportService.shared.requestAccessIfNeeded()
            loadSuggestions()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: NCSpacing.sm) {
            Text("Confirm follow-up times")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.ncInk)
            Text("NoteCrux found \(actionItems.count) follow-up\(actionItems.count == 1 ? "" : "s") in \"\(meetingTitle)\". Review each one, adjust the time if needed, and tap Add to save it to your calendar.")
                .font(.ncCallout)
                .foregroundStyle(Color.ncSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: NCSpacing.md) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.ncPurple)
            Text("No action items detected")
                .font(.ncHeadline)
                .foregroundStyle(Color.ncInk)
            Text("You can still add the meeting itself to your calendar from Settings → Calendar.")
                .font(.ncFootnote)
                .foregroundStyle(Color.ncMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, NCSpacing.xxl)
    }

    // MARK: - Logic

    private func loadSuggestions() {
        suggestions = actionItems.map { item in
            let combined = [item.title, item.detail].filter { !$0.isEmpty }.joined(separator: " ")
            let detected = CalendarImportService.detectDate(in: combined) ?? item.deadline
            let proposed = detected ?? defaultProposedDate()
            let autoDetected = detected != nil
            return ItemSuggestion(
                itemID: item.id,
                title: item.title.isEmpty ? "Follow-up" : item.title,
                detail: item.detail,
                proposedDate: proposed,
                autoDetected: autoDetected
            )
        }
    }

    private func defaultProposedDate() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + 1
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date().addingTimeInterval(86_400)
    }

    private func schedule(_ suggestion: ItemSuggestion) async {
        isWorking = true
        defer { isWorking = false }

        let id = await CalendarImportService.shared.createEvent(
            title: suggestion.title,
            startDate: suggestion.proposedDate,
            durationMinutes: 30,
            notes: suggestion.detail.isEmpty ? nil : suggestion.detail
        )
        if id != nil {
            scheduledIDs.insert(suggestion.itemID)
        }
    }
}

// MARK: - Row

private struct SchedulerRow: View {
    @Binding var suggestion: ItemSuggestion
    let isScheduled: Bool
    let onSchedule: () async -> Void

    @State private var isExpanded = false

    private var buttonLabel: String {
        if isScheduled { return "Added to Calendar" }
        return suggestion.autoDetected ? "Confirm & Add" : "Set Time & Add"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            HStack(alignment: .top, spacing: NCSpacing.md) {
                Image(systemName: isScheduled ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isScheduled ? Color.ncPurple : Color.ncMuted)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.ncHeadline)
                        .foregroundStyle(Color.ncInk)
                        .lineLimit(2)

                    if !suggestion.detail.isEmpty {
                        Text(suggestion.detail)
                            .font(.ncFootnote)
                            .foregroundStyle(Color.ncMuted)
                            .lineLimit(2)
                    }

                    if suggestion.autoDetected {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Time detected from transcript")
                        }
                        .font(.ncCaption2)
                        .foregroundStyle(Color.ncPurple)
                    }
                }

                Spacer()
            }

            DatePicker(
                "When",
                selection: $suggestion.proposedDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .tint(Color.ncPurple)
            .disabled(isScheduled)

            Button {
                Task { await onSchedule() }
            } label: {
                HStack {
                    Image(systemName: isScheduled ? "checkmark" : "calendar.badge.plus")
                    Text(buttonLabel)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(isScheduled ? Color.ncSuccess : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, NCSpacing.md)
                .background(
                    isScheduled
                        ? Color.ncSuccess.opacity(0.15)
                        : Color.ncPurple,
                    in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isScheduled)
        }
        .padding(NCSpacing.lg)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
    }
}

// MARK: - State

private struct ItemSuggestion: Identifiable {
    let itemID: UUID
    let title: String
    let detail: String
    var proposedDate: Date
    var autoDetected: Bool

    var id: UUID { itemID }
}
