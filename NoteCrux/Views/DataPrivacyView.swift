import SwiftData
import SwiftUI

struct DataPrivacyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    @Query private var folders: [MeetingFolder]
    @Query private var tasks: [MeetingActionItem]

    @AppStorage("nc_aiEnabled") private var aiEnabled = true
    @AppStorage("nc_autoProcessAfterRecording") private var autoProcess = true
    @AppStorage("nc_deleteAudioAfterProcessing") private var deleteAudioAfterProcessing = false
    @AppStorage("nc_keepTranscriptsOnly") private var keepTranscriptsOnly = false
    @AppStorage("selfDestructDays") private var selfDestructDays = 0
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("appLockBiometricsEnabled") private var appLockBiometricsEnabled = false
    @AppStorage("pinHash") private var pinHash = ""

    @State private var showDeleteAllConfirm = false
    @State private var showDeleteFinalConfirm = false
    @State private var showExportSuccess = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        ZStack {
            Color.ncBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: NCSpacing.xl + 4) {
                    privacyPromiseCard

                    aiProcessingSection

                    dataControlSection

                    securityStatusSection

                    dataInfoSection

                    storageShortcut

                    autoDeleteSection

                    legalSection
                }
                .padding(.horizontal, NCSpacing.lg + 2)
                .padding(.top, NCSpacing.md)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete All Data?", isPresented: $showDeleteAllConfirm) {
            Button("Continue", role: .destructive) {
                showDeleteFinalConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all meetings, tasks, transcripts, audio recordings, and cached data from this device.")
        }
        .alert("Are you absolutely sure?", isPresented: $showDeleteFinalConfirm) {
            Button("Delete Everything", role: .destructive) {
                deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All your NoteCrux data will be permanently removed.")
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(item: Binding(
            get: { exportURL.map { ExportURLWrapper(url: $0) } },
            set: { exportURL = $0?.url }
        )) { wrapper in
            MeetingShareSheet(items: [wrapper.url])
        }
    }

    // MARK: - Privacy Promise

    private var privacyPromiseCard: some View {
        VStack(alignment: .leading, spacing: NCSpacing.lg) {
            HStack(spacing: NCSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.ncSuccess.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.ncSuccess)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Data, Your Control")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.ncInk)
                    Text("Privacy by design")
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncSuccess)
                }
            }

            VStack(alignment: .leading, spacing: NCSpacing.md) {
                privacyBullet(icon: "iphone", text: "All meetings are stored locally on your device")
                privacyBullet(icon: "wifi.slash", text: "No data is sent anywhere without your action")
                privacyBullet(icon: "brain.head.profile.fill", text: "AI processing runs on-device when available")
                privacyBullet(icon: "lock.fill", text: "Your recordings and notes are never shared")
            }
        }
        .padding(NCSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .fill(Color.ncSuccess.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                        .strokeBorder(Color.ncSuccess.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func privacyBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: NCSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ncSuccess)
                .frame(width: 20)
            Text(text)
                .font(.ncCallout)
                .foregroundStyle(Color.ncSecondary)
        }
    }

    // MARK: - AI Processing

    private var aiProcessingSection: some View {
        SettingsSection(title: "AI PROCESSING") {
            SettingsCard {
                SettingsToggleRow(
                    icon: "sparkles",
                    iconColor: Color.ncPurple,
                    title: "Enable AI Features",
                    subtitle: "Summaries, task extraction, and insights",
                    isOn: $aiEnabled
                )

                SettingsDivider()

                SettingsToggleRow(
                    icon: "bolt.fill",
                    iconColor: Color.ncWarning,
                    title: "Auto-Process After Recording",
                    subtitle: aiEnabled ? "Generate insights automatically when recording ends" : "Requires AI features to be enabled",
                    isOn: $autoProcess
                )
                .disabled(!aiEnabled)
                .opacity(aiEnabled ? 1 : 0.5)
            }

            if !aiEnabled {
                HStack(spacing: NCSpacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ncMuted)
                    Text("AI features are disabled. Recordings will save transcript only.")
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)
                }
                .padding(.horizontal, NCSpacing.xs)
            }
        }
    }

    // MARK: - Data Control

    private var dataControlSection: some View {
        SettingsSection(title: "DATA CONTROL") {
            SettingsCard {
                Button { exportAllData() } label: {
                    SettingsDisclosureRow(
                        icon: "square.and.arrow.up.fill",
                        iconColor: Color.ncPurple,
                        title: "Export All Data",
                        subtitle: "Download meetings, transcripts, and tasks as JSON",
                        value: nil
                    )
                }
                .buttonStyle(SettingsRowPressStyle())
            }

            // Danger zone
            SettingsCard {
                Button { showDeleteAllConfirm = true } label: {
                    HStack(spacing: NCSpacing.md) {
                        SettingsIcon(icon: "trash.fill", color: Color.ncDanger)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete All Data")
                                .font(.ncHeadline)
                                .foregroundStyle(Color.ncDanger)
                            Text("Permanently remove all meetings, tasks, audio, and settings")
                                .font(.ncCaption1)
                                .foregroundStyle(Color.ncMuted)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ncDanger.opacity(0.5))
                    }
                    .padding(.horizontal, NCSpacing.lg)
                    .padding(.vertical, NCSpacing.md + 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsRowPressStyle())
            }
            .overlay(
                RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                    .strokeBorder(Color.ncDanger.opacity(0.10), lineWidth: 1)
            )
        }
    }

    // MARK: - Security Status

    private var securityStatusSection: some View {
        SettingsSection(title: "SECURITY") {
            SettingsCard {
                HStack(spacing: NCSpacing.md) {
                    SettingsIcon(icon: "lock.shield.fill", color: Color.ncSuccess)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Lock")
                            .font(.ncHeadline)
                            .foregroundStyle(Color.ncInk)
                        Text(securityStatusText)
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)
                    }

                    Spacer()

                    ZStack {
                        Capsule()
                            .fill(appLockEnabled ? Color.ncSuccess.opacity(0.12) : Color.ncDanger.opacity(0.12))
                            .frame(width: 70, height: 24)
                        Text(appLockEnabled ? "Active" : "Off")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(appLockEnabled ? Color.ncSuccess : Color.ncDanger)
                    }
                }
                .padding(.horizontal, NCSpacing.lg)
                .padding(.vertical, NCSpacing.md + 2)
            }
        }
    }

    private var securityStatusText: String {
        if !appLockEnabled { return "Not enabled — anyone can open the app" }
        var parts: [String] = []
        if appLockBiometricsEnabled { parts.append("Face ID / Touch ID") }
        if !pinHash.isEmpty { parts.append("PIN") }
        if parts.isEmpty { return "Enabled" }
        return parts.joined(separator: " + ") + " enabled"
    }

    // MARK: - Data Info

    private var dataInfoSection: some View {
        SettingsSection(title: "HOW YOUR DATA IS STORED") {
            SettingsCard {
                dataInfoRow(icon: "doc.text.fill", title: "\(meetings.count) meeting\(meetings.count == 1 ? "" : "s") stored locally")
                SettingsDivider()
                dataInfoRow(icon: "waveform", title: "\(audioCount) audio file\(audioCount == 1 ? "" : "s") on device")
                SettingsDivider()
                dataInfoRow(icon: "checkmark.circle.fill", title: "\(tasks.count) task\(tasks.count == 1 ? "" : "s") tracked")
                SettingsDivider()
                dataInfoRow(icon: "sparkles", title: "AI processing runs locally or on demand")
            }
        }
    }

    private var audioCount: Int {
        meetings.filter { $0.audioFilePath != nil }.count
    }

    private func dataInfoRow(icon: String, title: String) -> some View {
        HStack(spacing: NCSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ncMuted)
                .frame(width: 24)
            Text(title)
                .font(.ncCallout)
                .foregroundStyle(Color.ncSecondary)
            Spacer()
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md)
    }

    // MARK: - Storage Shortcut

    private var storageShortcut: some View {
        SettingsSection(title: "STORAGE") {
            SettingsCard {
                NavigationLink {
                    StorageManagementView()
                } label: {
                    SettingsDisclosureRow(
                        icon: "internaldrive.fill",
                        iconColor: Color(red: 0.31, green: 0.55, blue: 0.70),
                        title: "Manage Storage",
                        subtitle: "View usage breakdown and clean up files",
                        value: nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Auto-Delete / Advanced

    private var autoDeleteSection: some View {
        SettingsSection(title: "ADVANCED DATA SETTINGS") {
            SettingsCard {
                SettingsToggleRow(
                    icon: "speaker.slash.fill",
                    iconColor: Color.ncDanger,
                    title: "Delete Audio After Processing",
                    subtitle: "Keep transcript and summary, remove recording file",
                    isOn: $deleteAudioAfterProcessing
                )

                SettingsDivider()

                SettingsToggleRow(
                    icon: "doc.plaintext.fill",
                    iconColor: Color.ncSecondary,
                    title: "Keep Transcripts Only",
                    subtitle: "Remove AI summaries when cleaning up old meetings",
                    isOn: $keepTranscriptsOnly
                )

                SettingsDivider()

                HStack(spacing: NCSpacing.md) {
                    SettingsIcon(icon: "clock.arrow.circlepath", color: Color.ncWarning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Delete Old Meetings")
                            .font(.ncHeadline)
                            .foregroundStyle(Color.ncInk)
                        Text(selfDestructDays == 0 ? "Disabled — meetings kept forever" : "After \(selfDestructDays) days")
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)
                    }

                    Spacer()

                    Picker("", selection: $selfDestructDays) {
                        Text("Off").tag(0)
                        Text("30d").tag(30)
                        Text("60d").tag(60)
                        Text("90d").tag(90)
                        Text("1y").tag(365)
                    }
                    .pickerStyle(.menu)
                    .tint(Color.ncPurple)
                }
                .padding(.horizontal, NCSpacing.lg)
                .padding(.vertical, NCSpacing.md + 2)
            }
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        SettingsSection(title: "LEGAL") {
            SettingsCard {
                Link(destination: URL(string: "https://www.notion.so/NoteCrux-Privacy-Policy-348ea5c71e68803c9c55fabf36d025fc")!) {
                    SettingsDisclosureRow(
                        icon: "hand.raised.fill",
                        iconColor: Color.ncPurple,
                        title: "Privacy Policy",
                        value: nil
                    )
                }
                .buttonStyle(SettingsRowPressStyle())

                SettingsDivider()

                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    SettingsDisclosureRow(
                        icon: "doc.text.fill",
                        iconColor: Color.ncSecondary,
                        title: "Terms of Service",
                        value: nil
                    )
                }
                .buttonStyle(SettingsRowPressStyle())
            }
        }
    }

    // MARK: - Actions

    private func exportAllData() {
        do {
            let url = try LocalBackupService.export(meetings: meetings, folders: folders, tasks: tasks)
            exportURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func deleteAllData() {
        // Delete all meetings (cascade deletes action items)
        for meeting in meetings {
            modelContext.delete(meeting)
        }
        try? modelContext.save()

        // Delete local files
        LocalBackupService.deleteLocalFiles()

        // Clear exports
        StorageManager.shared.deleteExports()
        StorageManager.shared.clearCache()

        // Reset draft
        UserDefaults.standard.removeObject(forKey: "activeRecordingDraft")
    }
}

// MARK: - URL Wrapper

private struct ExportURLWrapper: Identifiable {
    let id = UUID()
    let url: URL
}
