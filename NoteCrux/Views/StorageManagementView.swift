import SwiftData
import SwiftUI

struct StorageManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    private var storage = StorageManager.shared

    @State private var showClearCacheConfirm = false
    @State private var showDeleteExportsConfirm = false
    @State private var showDeleteBackupsConfirm = false
    @State private var showDeleteAudioConfirm = false
    @State private var selectedAudioMeetings: Set<UUID> = []
    @State private var showAudioPicker = false
    @State private var toastMessage: String?

    var body: some View {
        ZStack {
            Color.ncBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: NCSpacing.xl + 4) {
                    headerSection

                    totalStorageCard

                    if let suggestion = storage.cleanupSuggestion {
                        suggestionBanner(suggestion)
                    }

                    breakdownSection

                    if !storage.largeMeetings.isEmpty {
                        largeMeetingsSection
                    }

                    cleanupSection
                }
                .padding(.horizontal, NCSpacing.lg + 2)
                .padding(.top, NCSpacing.md)
                .padding(.bottom, 40)
            }

            if let toast = toastMessage {
                VStack {
                    Spacer()
                    toastView(toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
                .animation(.ncSpring, value: toastMessage)
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            storage.loadStorageUsage(meetings: meetings)
        }
        .confirmationDialog("Clear Cache", isPresented: $showClearCacheConfirm, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) {
                storage.clearCache()
                reload()
                showToast("Cache cleared")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes temporary processing files only. Your meetings, recordings, and notes will not be affected.")
        }
        .confirmationDialog("Delete Exports", isPresented: $showDeleteExportsConfirm, titleVisibility: .visible) {
            Button("Delete All Exports", role: .destructive) {
                storage.deleteExports()
                reload()
                showToast("Exports deleted")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes exported files saved locally. Your original meetings and recordings will remain untouched.")
        }
        .confirmationDialog("Delete Backups", isPresented: $showDeleteBackupsConfirm, titleVisibility: .visible) {
            Button("Delete All Backups", role: .destructive) {
                storage.deleteBackups()
                reload()
                showToast("Backups deleted")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes locally saved JSON backup files. Your meetings and recordings will not be affected.")
        }
        .confirmationDialog("Delete Audio Files", isPresented: $showDeleteAudioConfirm, titleVisibility: .visible) {
            Button("Delete Audio (\(selectedAudioMeetings.count) meetings)", role: .destructive) {
                deleteSelectedAudio()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the audio recording files but keeps the transcript, summary, and all notes for the selected meetings.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: NCSpacing.xs) {
            HStack(spacing: NCSpacing.sm) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ncPurple)
                Text("LOCAL STORAGE")
                    .font(.ncOverline)
                    .tracking(1.4)
                    .foregroundStyle(Color.ncMuted)
            }

            Text("All your data is stored locally on this device")
                .font(.ncFootnote)
                .foregroundStyle(Color.ncSecondary)
        }
        .padding(.top, NCSpacing.sm)
    }

    // MARK: - Total Storage Card

    private var totalStorageCard: some View {
        NCCard {
            VStack(spacing: NCSpacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: NCSpacing.xs) {
                        Text("Total Used")
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)

                        if storage.isLoading {
                            ProgressView()
                        } else {
                            Text(StorageManager.formattedSize(storage.totalBytesUsed))
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(Color.ncInk)
                        }
                    }

                    Spacer()

                    StorageRing(breakdown: storage.breakdown, total: storage.totalBytesUsed)
                        .frame(width: 72, height: 72)
                }

                // Category legend
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: NCSpacing.sm) {
                    ForEach(storage.breakdown.filter { $0.bytes > 0 }) { item in
                        HStack(spacing: NCSpacing.xs) {
                            Circle()
                                .fill(categoryColor(item.category))
                                .frame(width: 8, height: 8)
                            Text(item.category.rawValue)
                                .font(.ncCaption2)
                                .foregroundStyle(Color.ncMuted)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Suggestion Banner

    private func suggestionBanner(_ text: String) -> some View {
        HStack(spacing: NCSpacing.md) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ncWarning)

            Text(text)
                .font(.ncCaption1)
                .foregroundStyle(Color.ncInk)

            Spacer()
        }
        .padding(NCSpacing.md)
        .background(Color.ncWarning.opacity(0.06), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                .strokeBorder(Color.ncWarning.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Breakdown Section

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            Text("BREAKDOWN")
                .font(.ncOverline)
                .tracking(1.4)
                .foregroundStyle(Color.ncMuted)

            NCCard(padding: 0) {
                ForEach(Array(storage.breakdown.enumerated()), id: \.element.id) { index, item in
                    StorageBreakdownRow(item: item, color: categoryColor(item.category))

                    if index < storage.breakdown.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    // MARK: - Large Meetings Section

    private var largeMeetingsSection: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            Text("LARGEST RECORDINGS")
                .font(.ncOverline)
                .tracking(1.4)
                .foregroundStyle(Color.ncMuted)

            NCCard(padding: 0) {
                ForEach(Array(storage.largeMeetings.prefix(5).enumerated()), id: \.element.id) { index, item in
                    LargeMeetingRow(
                        item: item,
                        isSelected: selectedAudioMeetings.contains(item.id),
                        toggle: {
                            if selectedAudioMeetings.contains(item.id) {
                                selectedAudioMeetings.remove(item.id)
                            } else {
                                selectedAudioMeetings.insert(item.id)
                            }
                        }
                    )

                    if index < min(storage.largeMeetings.count, 5) - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }

            if !selectedAudioMeetings.isEmpty {
                Button {
                    showDeleteAudioConfirm = true
                } label: {
                    HStack(spacing: NCSpacing.sm) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Delete Audio for \(selectedAudioMeetings.count) Meeting\(selectedAudioMeetings.count == 1 ? "" : "s")")
                            .font(.ncCallout.bold())
                    }
                    .foregroundStyle(Color.ncDanger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NCSpacing.md)
                    .background(Color.ncDanger.opacity(0.06), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                            .strokeBorder(Color.ncDanger.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Cleanup Section

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            Text("CLEANUP")
                .font(.ncOverline)
                .tracking(1.4)
                .foregroundStyle(Color.ncMuted)

            NCCard(padding: 0) {
                cleanupRow(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: Color.ncSecondary,
                    title: "Clear Cache",
                    subtitle: "Remove temporary processing files",
                    size: storage.breakdown.first(where: { $0.category == .cache })?.bytes ?? 0
                ) {
                    showClearCacheConfirm = true
                }

                Divider().padding(.leading, 56)

                cleanupRow(
                    icon: "square.and.arrow.up.fill",
                    iconColor: Color.ncDanger,
                    title: "Delete Exports",
                    subtitle: "Remove saved export files",
                    size: storage.breakdown.first(where: { $0.category == .exports })?.bytes ?? 0
                ) {
                    showDeleteExportsConfirm = true
                }

                Divider().padding(.leading, 56)

                cleanupRow(
                    icon: "externaldrive.fill",
                    iconColor: Color.ncMuted,
                    title: "Delete Backups",
                    subtitle: "Remove local JSON backup files",
                    size: storage.breakdown.first(where: { $0.category == .backups })?.bytes ?? 0
                ) {
                    showDeleteBackupsConfirm = true
                }
            }
        }
    }

    private func cleanupRow(icon: String, iconColor: Color, title: String, subtitle: String, size: Int64, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NCSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.10))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ncHeadline)
                        .foregroundStyle(Color.ncInk)
                    Text(subtitle)
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)
                }

                Spacer()

                if size > 0 {
                    Text(StorageManager.formattedSize(size))
                        .font(.ncCaption1.weight(.semibold))
                        .foregroundStyle(Color.ncSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ncMuted.opacity(0.5))
            }
            .padding(.horizontal, NCSpacing.lg)
            .padding(.vertical, NCSpacing.md + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(size == 0)
        .opacity(size == 0 ? 0.5 : 1)
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: NCSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ncSuccess)
            Text(message)
                .font(.ncCallout.weight(.semibold))
                .foregroundStyle(Color.ncInk)
        }
        .padding(.horizontal, NCSpacing.xl)
        .padding(.vertical, NCSpacing.md)
        .background(.ultraThinMaterial, in: Capsule())
        .ncShadow(.card)
    }

    // MARK: - Actions

    private func reload() {
        storage.loadStorageUsage(meetings: meetings)
    }

    private func deleteSelectedAudio() {
        let selected = meetings.filter { selectedAudioMeetings.contains($0.id) }
        storage.deleteAudio(for: selected)
        try? modelContext.save()
        selectedAudioMeetings.removeAll()
        reload()
        showToast("Audio files deleted")
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toastMessage = nil }
        }
    }

    // MARK: - Category Colors

    private func categoryColor(_ category: StorageCategory) -> Color {
        switch category {
        case .audio: return Color.ncPurple
        case .meetings: return Color.ncInk
        case .transcripts: return Color.ncSuccess
        case .insights: return Color.ncWarning
        case .exports: return Color.ncDanger
        case .backups: return Color(red: 0.31, green: 0.55, blue: 0.70)
        case .cache: return Color.ncSecondary
        }
    }
}

// MARK: - Storage Ring

private struct StorageRing: View {
    let breakdown: [StorageBreakdownItem]
    let total: Int64

    private func segmentColor(_ category: StorageCategory) -> Color {
        switch category {
        case .audio: return Color.ncPurple
        case .meetings: return Color.ncInk
        case .transcripts: return Color.ncSuccess
        case .insights: return Color.ncWarning
        case .exports: return Color.ncDanger
        case .backups: return Color(red: 0.31, green: 0.55, blue: 0.70)
        case .cache: return Color.ncSecondary
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ncDivider.opacity(0.3), lineWidth: 8)

            if total > 0 {
                let nonZero = breakdown.filter { $0.bytes > 0 }
                let fractions: [(Double, Color)] = nonZero.map { item in
                    (Double(item.bytes) / Double(total), segmentColor(item.category))
                }

                ForEach(Array(fractions.enumerated()), id: \.offset) { index, segment in
                    let start = fractions.prefix(index).reduce(0.0) { $0 + $1.0 }
                    Circle()
                        .trim(from: start, to: start + segment.0)
                        .stroke(segment.1, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }

            Image(systemName: "internaldrive.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.ncMuted)
        }
    }
}

// MARK: - Breakdown Row

private struct StorageBreakdownRow: View {
    let item: StorageBreakdownItem
    let color: Color

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.10))
                    .frame(width: 36, height: 36)

                Image(systemName: item.category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)
                Text("\(item.count) item\(item.count == 1 ? "" : "s")")
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncMuted)
            }

            Spacer()

            Text(StorageManager.formattedSize(item.bytes))
                .font(.ncCallout.weight(.semibold))
                .foregroundStyle(Color.ncSecondary)
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md + 2)
    }
}

// MARK: - Large Meeting Row

private struct LargeMeetingRow: View {
    let item: LargeMeetingItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: NCSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.ncPurple : Color.ncDivider, lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.ncPurple)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.ncHeadline)
                        .foregroundStyle(Color.ncInk)
                        .lineLimit(1)
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)
                }

                Spacer()

                Text(StorageManager.formattedSize(item.audioBytes))
                    .font(.ncCallout.weight(.semibold))
                    .foregroundStyle(Color.ncPurple)
            }
            .padding(.horizontal, NCSpacing.lg)
            .padding(.vertical, NCSpacing.md + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
