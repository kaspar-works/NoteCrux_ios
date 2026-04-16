import OSLog
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    @Query private var folders: [MeetingFolder]
    @Query private var tasks: [MeetingActionItem]
    @Query(sort: \Meeting.createdAt, order: .reverse) private var allMeetings: [Meeting]

    @AppStorage("modelMode") private var modelMode = "Battery-Saver"
    @AppStorage("selfDestructDays") private var selfDestructDays = 0
    @AppStorage("requireBiometrics") private var requireBiometrics = true
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @AppStorage("appLockBiometricsEnabled") private var appLockBiometricsEnabled = true
    @AppStorage("pinHash") private var pinHash = ""
    @AppStorage("themeMode") private var themeMode = "System"
    @AppStorage("focusReadingMode") private var focusReadingMode = false
    @AppStorage("languageMode") private var languageMode = "English"

    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var backupURL: URL?
    @State private var statusMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var bulkExportURL: URL? = nil
    @State private var bulkExportError: String? = nil
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: NCSpacing.xxl) {
                        ProfileTopBar()

                        ProfileIdentity()

                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            NCSectionHeader(title: "SECURITY & PRIVACY")
                                .padding(.horizontal, NCSpacing.md)

                            ProfileCard {
                                ProfileToggleRow(
                                    icon: "faceid",
                                    iconColor: .ncPurple,
                                    title: "App Lock",
                                    subtitle: "Use Face ID to secure NoteCrux",
                                    isOn: $appLockEnabled
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            NCSectionHeader(title: "APPEARANCE")
                                .padding(.horizontal, NCSpacing.md)

                            ProfileCard(spacing: 0) {
                                NavigationLink {
                                    ThemeProfileSettings(themeMode: $themeMode, focusReadingMode: $focusReadingMode)
                                } label: {
                                    ProfileDisclosureRow(
                                        icon: "paintpalette.fill",
                                        iconColor: .ncPurple,
                                        title: "Theme",
                                        value: themeMode
                                    )
                                }
                                .buttonStyle(.plain)

                                ProfileDivider()

                                NavigationLink {
                                    LanguageProfileSettings(languageMode: $languageMode)
                                } label: {
                                    ProfileDisclosureRow(
                                        icon: "globe.americas.fill",
                                        iconColor: Color(red: 0.64, green: 0.31, blue: 0.24),
                                        title: "Language",
                                        value: languageMode
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            NCSectionHeader(title: "DATA MANAGEMENT")
                                .padding(.horizontal, NCSpacing.md)

                            ProfileCard(spacing: 0) {
                                Button {
                                    createBackup()
                                } label: {
                                    ProfileDisclosureRow(
                                        icon: "doc.text.fill",
                                        iconColor: Color.ncMuted,
                                        title: backupURL == nil ? "Export JSON" : "Export Ready",
                                        value: nil
                                    )
                                }
                                .buttonStyle(.plain)

                                if let backupURL {
                                    ProfileDivider()

                                    ShareLink(item: backupURL) {
                                        ProfileDisclosureRow(
                                            icon: "square.and.arrow.up.fill",
                                            iconColor: .ncPurple,
                                            title: "Share Backup",
                                            value: nil
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                ProfileDivider()

                                Button(role: .destructive) {
                                    showDeleteConfirmation = true
                                } label: {
                                    ProfileDangerRow()
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: NCSpacing.md) {
                            NCSectionHeader(title: "BULK EXPORT")
                                .padding(.horizontal, NCSpacing.md)

                            ProfileCard(spacing: 0) {
                                Button {
                                    Task {
                                        isExporting = true
                                        defer { isExporting = false }
                                        do {
                                            bulkExportURL = try MeetingExportService.exportAll(allMeetings)
                                        } catch {
                                            bulkExportError = error.localizedDescription
                                            NoteCruxLog.export.debug("Bulk export failed: \(String(describing: error), privacy: .public)")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 14) {
                                        ProfileIcon(
                                            icon: "arrow.up.doc.on.clipboard",
                                            color: Color(red: 0.04, green: 0.42, blue: 0.43)
                                        )

                                        Text(isExporting ? "Preparing archive…" : "Export all meetings")
                                            .font(.ncHeadline)
                                            .foregroundStyle(Color.ncInk)

                                        Spacer()

                                        if isExporting {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.ncCaption2)
                                                .foregroundStyle(Color.ncMuted.opacity(0.75))
                                        }
                                    }
                                    .padding(.horizontal, NCSpacing.lg)
                                    .padding(.vertical, 15)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isExporting || allMeetings.isEmpty)
                            }

                            Text("Creates a zip of markdown files. Audio files are available via the per-meeting share button.")
                                .font(.caption)
                                .foregroundStyle(Color.ncMuted)
                                .padding(.horizontal, NCSpacing.md)
                        }

                        PrivacyGuaranteeCard()

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.ncFootnote.bold())
                                .foregroundStyle(Color.ncMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, NCSpacing.xl)
                        }

                        VStack(spacing: NCSpacing.xs) {
                            Text("VERSION 2.1 STABLE")
                                .font(.ncOverline)
                                .tracking(1.6)
                                .foregroundStyle(Color.ncMuted)

                            Text("© 2024 NoteCrux AI Lab")
                                .font(.ncOverline)
                                .foregroundStyle(Color.ncMuted.opacity(0.72))
                        }
                        .padding(.top, -2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, NCSpacing.lg)
                    .padding(.bottom, 92)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: Binding(
                get: { bulkExportURL.map { BulkExportWrapper(url: $0) } },
                set: { bulkExportURL = $0?.url }
            )) { wrapper in
                MeetingShareSheet(items: [wrapper.url])
            }
            .alert("Export failed", isPresented: Binding(
                get: { bulkExportError != nil },
                set: { if !$0 { bulkExportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bulkExportError ?? "")
            }
            .confirmationDialog(
                "Delete all local NoteCrux data?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Data", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes meetings, folders, tasks, local recordings, backups, and unsaved recording drafts from this device.")
            }
        }
    }

    private func savePIN() {
        guard pin.count >= 4, pin == confirmPIN else {
            statusMessage = "PIN must be at least 4 digits and match confirmation."
            return
        }

        pinHash = AppSecurity.hashPIN(pin)
        pin = ""
        confirmPIN = ""
        statusMessage = "PIN saved."
    }

    private func createBackup() {
        do {
            backupURL = try LocalBackupService.export(meetings: meetings, folders: folders, tasks: tasks)
            statusMessage = "Local JSON backup created."
        } catch {
            statusMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func deleteAllData() {
        for task in tasks {
            TaskReminderScheduler.cancel(identifier: task.notificationIdentifier)
            modelContext.delete(task)
        }

        for meeting in meetings {
            modelContext.delete(meeting)
        }

        for folder in folders {
            modelContext.delete(folder)
        }

        LocalBackupService.deleteLocalFiles()
        backupURL = nil
        try? modelContext.save()
        statusMessage = "All local meeting data deleted."
    }
}

private struct ProfileTopBar: View {
    var body: some View {
        HStack(spacing: NCSpacing.md) {
            ZStack {
                Circle()
                    .fill(NoteCruxTheme.brandGradient)

                Image(systemName: "waveform")
                    .font(.ncFootnote.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            Text("NoteCrux")
                .font(.ncTitle3)
                .foregroundStyle(Color.ncInk)

            Spacer()

            Image(systemName: "gearshape.fill")
                .font(.ncTitle2)
                .foregroundStyle(Color.ncPurple)
                .frame(width: 34, height: 34)
        }
    }
}

private struct ProfileIdentity: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AvatarPortrait()
                    .frame(width: 102, height: 102)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.ncPurple, lineWidth: 4))
                    .shadow(color: Color.ncPurple.opacity(0.18), radius: 14, y: 7)

                ZStack {
                    Circle()
                        .fill(Color.ncPurple)
                    Circle()
                        .fill(.white)
                        .frame(width: 9, height: 9)
                }
                .frame(width: 25, height: 25)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            }

            Text("Alex Thompson")
                .font(.ncTitle1)
                .foregroundStyle(Color.ncInk)

            Label("LOCAL ONLY", systemImage: "lock.fill")
                .font(.ncCaption2)
                .tracking(1.1)
                .foregroundStyle(Color.ncPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.ncPurple.opacity(0.09), in: Capsule())
        }
        .padding(.top, 2)
    }
}

private struct AvatarPortrait: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.12, blue: 0.16),
                    Color(red: 0.03, green: 0.40, blue: 0.38),
                    Color(red: 0.11, green: 0.17, blue: 0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Ellipse()
                .fill(Color(red: 0.16, green: 0.56, blue: 0.50))
                .frame(width: 52, height: 70)
                .offset(y: 6)

            HStack(spacing: 14) {
                Circle().fill(Color(red: 0.75, green: 0.92, blue: 0.82))
                Circle().fill(Color(red: 0.75, green: 0.92, blue: 0.82))
            }
            .frame(width: 40, height: 8)
            .offset(y: -4)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.02, green: 0.18, blue: 0.18))
                .frame(width: 24, height: 4)
                .offset(y: 23)

            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(.black.opacity(0.24))
                    .frame(width: 3, height: 92)
                    .offset(x: CGFloat(index - 2) * 16)
            }
        }
    }
}

private struct ProfileCard<Content: View>: View {
    var spacing: CGFloat = NCSpacing.md
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .ncShadow(.card)
    }
}

private struct ProfileToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ProfileIcon(icon: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                Text(subtitle)
                    .font(.ncCaption1.bold())
                    .foregroundStyle(Color.ncMuted)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.ncPurple)
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, 13)
    }
}

private struct ProfileDisclosureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String?

    var body: some View {
        HStack(spacing: 14) {
            ProfileIcon(icon: icon, color: iconColor)

            Text(title)
                .font(.ncHeadline)
                .foregroundStyle(Color.ncInk)

            Spacer()

            if let value {
                Text(value)
                    .font(.ncCaption1.bold())
                    .foregroundStyle(Color.ncMuted)
            }

            Image(systemName: "chevron.right")
                .font(.ncCaption2)
                .foregroundStyle(Color.ncMuted.opacity(0.75))
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

private struct ProfileDangerRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ProfileIcon(icon: "trash.fill", color: Color.ncDanger)

            Text("Delete Account")
                .font(.ncHeadline)
                .foregroundStyle(Color.ncDanger)

            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.ncCaption2)
                .foregroundStyle(Color.ncDanger.opacity(0.5))
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

private struct ProfileIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 35, height: 35)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct ProfileDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.ncBackground)
            .frame(height: 1)
            .padding(.leading, 65)
    }
}

private struct PrivacyGuaranteeCard: View {
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: "sparkles")
                .font(.ncTitle3)
                .foregroundStyle(Color.ncPurple)

            Text("Privacy Guarantee")
                .font(.ncHeadline)
                .foregroundStyle(Color.ncInk)

            Text("NoteCrux is local-first encryption. Your financial data never leaves this device without your permission.")
                .font(.ncFootnote)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ncMuted)
                .padding(.horizontal, NCSpacing.xl)

            Text("Read Privacy Policy")
                .font(.ncFootnote.bold())
                .foregroundStyle(Color.ncPurple)
                .padding(.top, NCSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color.ncPurple.opacity(0.055), in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
    }
}

private struct ThemeProfileSettings: View {
    @Binding var themeMode: String
    @Binding var focusReadingMode: Bool

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $themeMode) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }

                Toggle("Focus Reading Mode", isOn: $focusReadingMode)
            }
        }
        .navigationTitle("Theme")
    }
}

private struct LanguageProfileSettings: View {
    @Binding var languageMode: String

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $languageMode) {
                    Text("English").tag("English")
                    Text("Spanish").tag("Spanish")
                    Text("French").tag("French")
                    Text("German").tag("German")
                }
            }
        }
        .navigationTitle("Language")
    }
}

private struct BulkExportWrapper: Identifiable {
    let id = UUID()
    let url: URL
}
