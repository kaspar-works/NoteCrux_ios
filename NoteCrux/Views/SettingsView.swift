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
                Color.profileBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        ProfileTopBar()

                        ProfileIdentity()

                        VStack(alignment: .leading, spacing: 11) {
                            ProfileSectionTitle("SECURITY & PRIVACY")

                            ProfileCard {
                                ProfileToggleRow(
                                    icon: "faceid",
                                    iconColor: .profilePurple,
                                    title: "App Lock",
                                    subtitle: "Use Face ID to secure NoteCrux",
                                    isOn: $appLockEnabled
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: 11) {
                            ProfileSectionTitle("APPEARANCE")

                            ProfileCard(spacing: 0) {
                                NavigationLink {
                                    ThemeProfileSettings(themeMode: $themeMode, focusReadingMode: $focusReadingMode)
                                } label: {
                                    ProfileDisclosureRow(
                                        icon: "paintpalette.fill",
                                        iconColor: .profilePurple,
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

                        VStack(alignment: .leading, spacing: 11) {
                            ProfileSectionTitle("DATA MANAGEMENT")

                            ProfileCard(spacing: 0) {
                                Button {
                                    createBackup()
                                } label: {
                                    ProfileDisclosureRow(
                                        icon: "doc.text.fill",
                                        iconColor: Color(red: 0.33, green: 0.35, blue: 0.40),
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
                                            iconColor: .profilePurple,
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

                        VStack(alignment: .leading, spacing: 11) {
                            ProfileSectionTitle("BULK EXPORT")

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
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(Color.profileInk)

                                        Spacer()

                                        if isExporting {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Color.profileMuted.opacity(0.75))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 15)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isExporting || allMeetings.isEmpty)
                            }

                            Text("Creates a zip of markdown files. Audio files are available via the per-meeting share button.")
                                .font(.caption)
                                .foregroundStyle(Color.profileMuted)
                                .padding(.horizontal, 12)
                        }

                        PrivacyGuaranteeCard()

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.profileMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        VStack(spacing: 4) {
                            Text("VERSION 2.1 STABLE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.6)
                                .foregroundStyle(Color.profileMuted)

                            Text("© 2024 NoteCrux AI Lab")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.profileMuted.opacity(0.72))
                        }
                        .padding(.top, -2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.04, green: 0.42, blue: 0.43), Color(red: 0.97, green: 0.72, blue: 0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            Text("NoteCrux")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.profileInk)

            Spacer()

            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.profilePurple)
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
                    .overlay(Circle().stroke(Color.profilePurple, lineWidth: 4))
                    .shadow(color: Color.profilePurple.opacity(0.18), radius: 14, y: 7)

                ZStack {
                    Circle()
                        .fill(Color.profilePurple)
                    Circle()
                        .fill(.white)
                        .frame(width: 9, height: 9)
                }
                .frame(width: 25, height: 25)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            }

            Text("Alex Thompson")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.profileInk)

            Label("LOCAL ONLY", systemImage: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Color.profilePurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.profilePurple.opacity(0.09), in: Capsule())
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

private struct ProfileSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(Color.profileMuted)
            .padding(.horizontal, 12)
    }
}

private struct ProfileCard<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity)
        .background(Color.profileSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .shadow(color: .black.opacity(0.025), radius: 14, y: 7)
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.profileInk)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.profileMuted)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.profilePurple)
        }
        .padding(.horizontal, 16)
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.profileInk)

            Spacer()

            if let value {
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.profileMuted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.profileMuted.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

private struct ProfileDangerRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ProfileIcon(icon: "trash.fill", color: Color(red: 0.86, green: 0.18, blue: 0.18))

            Text("Delete Account")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.79, green: 0.12, blue: 0.13))

            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.79, green: 0.12, blue: 0.13).opacity(0.5))
        }
        .padding(.horizontal, 16)
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
            .fill(Color.profileBackground)
            .frame(height: 1)
            .padding(.leading, 65)
    }
}

private struct PrivacyGuaranteeCard: View {
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.profilePurple)

            Text("Privacy Guarantee")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.profileInk)

            Text("NoteCrux is local-first encryption. Your financial data never leaves this device without your permission.")
                .font(.system(size: 12, weight: .medium))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.profileMuted)
                .padding(.horizontal, 20)

            Text("Read Privacy Policy")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.profilePurple)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color.profilePurple.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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

private extension Color {
    static let profileBackground = Color.adaptive(light: (0.978, 0.976, 0.984), dark: (0.055, 0.056, 0.072))
    static let profileSurface = Color.adaptive(light: (1.0, 1.0, 1.0), dark: (0.105, 0.108, 0.135))
    static let profileInk = Color.adaptive(light: (0.14, 0.14, 0.16), dark: (0.93, 0.94, 0.97))
    static let profileMuted = Color.adaptive(light: (0.57, 0.57, 0.64), dark: (0.62, 0.64, 0.72))
    static let profilePurple = Color.adaptive(light: (0.25, 0.18, 0.86), dark: (0.58, 0.50, 1.0))
}
