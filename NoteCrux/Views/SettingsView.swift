import OSLog
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    @Query private var folders: [MeetingFolder]
    @Query private var tasks: [MeetingActionItem]
    @Query(sort: \Meeting.createdAt, order: .reverse) private var allMeetings: [Meeting]

    @AppStorage("selfDestructDays") private var selfDestructDays = 0
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("appLockBiometricsEnabled") private var appLockBiometricsEnabled = false
    @AppStorage("pinHash") private var pinHash = ""
    @AppStorage("themeMode") private var themeMode = "System"
    @AppStorage("focusReadingMode") private var focusReadingMode = false
    @AppStorage("nc_iCloudSyncEnabled") private var iCloudSyncEnabled = false

    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var backupURL: URL?
    @State private var statusMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var bulkExportURL: URL? = nil
    @State private var bulkExportError: String? = nil
    @State private var isExporting = false
    @State private var showContent = false
    @State private var exportSuccess = false
    @State private var showPaywall = false
    @State private var showPINRequiredAlert = false
    @State private var navigateToPINSetup = false
    @State private var showICloudRestartAlert = false

    private var biometricToggleBinding: Binding<Bool> {
        Binding(
            get: { appLockBiometricsEnabled },
            set: { newValue in
                if !newValue && pinHash.isEmpty {
                    showPINRequiredAlert = true
                } else {
                    appLockBiometricsEnabled = newValue
                }
            }
        )
    }

    private var appLockToggleBinding: Binding<Bool> {
        Binding(
            get: { appLockEnabled },
            set: { newValue in
                if newValue && !appLockBiometricsEnabled && pinHash.isEmpty {
                    showPINRequiredAlert = true
                } else {
                    appLockEnabled = newValue
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.ncBackground, Color.ncBackground, Color.ncPurple.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: NCSpacing.xl + 4) {
                        // Identity header
                        SettingsIdentityHeader()
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 12)

                        // Subscription section
                        subscriptionSection
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 14)

                        // Security section
                        securitySection
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 14)

                        // Appearance section
                        appearanceSection
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)

                        // Data section
                        dataSection
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)

                        // Storage section
                        storageSection
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)

                        // Export section
                        exportSection
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)

                        // Privacy card
                        PrivacyGuaranteeCard()
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 16)

                        // Status message
                        if let statusMessage {
                            StatusToast(message: statusMessage, isSuccess: !statusMessage.contains("failed"))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Footer
                        SettingsFooter()
                            .opacity(showContent ? 1 : 0)
                    }
                    .padding(.horizontal, NCSpacing.lg + 2)
                    .padding(.top, NCSpacing.md)
                    .padding(.bottom, 94)
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
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove all meetings, tasks, recordings, backups, and drafts from this device. This cannot be undone.")
            }
            .alert("Restart Required", isPresented: $showICloudRestartAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(iCloudSyncEnabled
                     ? "iCloud Sync will take effect the next time you launch NoteCrux. Meetings will sync to devices signed into the same iCloud account. Audio files stay on this device."
                     : "iCloud Sync will be disabled on the next launch. Meetings already synced will remain in iCloud until you turn it off in iCloud settings.")
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
        }
    }

    // MARK: - Remove Ads Section

    private var subscriptionSection: some View {
        SettingsSection(title: "ADS") {
            if SubscriptionManager.shared.isSubscribed {
                SettingsCard {
                    HStack(spacing: NCSpacing.md) {
                        SettingsIcon(icon: "checkmark.seal.fill", color: Color.ncPurple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ads Removed")
                                .font(.ncHeadline)
                                .foregroundStyle(Color.ncInk)
                            Text("Thanks for supporting NoteCrux")
                                .font(.ncCaption1)
                                .foregroundStyle(Color.ncMuted)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, NCSpacing.lg)
                    .padding(.vertical, NCSpacing.md + 2)
                }
            } else {
                SettingsCard {
                    VStack(spacing: NCSpacing.md) {
                        HStack(spacing: NCSpacing.md) {
                            SettingsIcon(icon: "sparkles", color: Color.ncPurple)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remove Ads")
                                    .font(.ncHeadline)
                                    .foregroundStyle(Color.ncInk)
                                Text("One-time purchase. All features stay free.")
                                    .font(.ncCaption1)
                                    .foregroundStyle(Color.ncMuted)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, NCSpacing.lg)
                        .padding(.top, NCSpacing.md + 2)

                        Button { showPaywall = true } label: {
                            Text("Remove Ads")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, NCSpacing.md)
                                .background(Color.ncPurple, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                        }
                        .buttonStyle(NCPressButtonStyle())
                        .padding(.horizontal, NCSpacing.lg)
                        .padding(.bottom, NCSpacing.md + 2)
                    }
                }

                Button {
                    Task { await SubscriptionManager.shared.restorePurchases() }
                } label: {
                    Text("Restore Purchase")
                        .font(.ncCaption1.weight(.semibold))
                        .foregroundStyle(Color.ncPurple)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, NCSpacing.xs)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("Set a PIN first", isPresented: $showPINRequiredAlert) {
            Button("Set PIN") { navigateToPINSetup = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set a backup PIN before locking the app. Without a PIN you could be locked out if Face ID or Touch ID is ever unavailable.")
        }
        .navigationDestination(isPresented: $navigateToPINSetup) {
            PINSetupView(pinHash: $pinHash, statusMessage: $statusMessage)
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        SettingsSection(title: "SECURITY & PRIVACY") {
            SettingsCard {
                SettingsToggleRow(
                    icon: "faceid",
                    iconColor: Color.ncPurple,
                    title: "App Lock",
                    subtitle: "Use Face ID to protect your data",
                    isOn: appLockToggleBinding
                )

                SettingsDivider()

                SettingsToggleRow(
                    icon: "hand.raised.fill",
                    iconColor: Color(red: 0.31, green: 0.55, blue: 0.70),
                    title: "Biometric Unlock",
                    subtitle: "Allow Face ID / Touch ID to unlock",
                    isOn: biometricToggleBinding
                )

                SettingsDivider()

                NavigationLink {
                    PINSetupView(pinHash: $pinHash, statusMessage: $statusMessage)
                } label: {
                    SettingsDisclosureRow(
                        icon: "lock.fill",
                        iconColor: Color.ncWarning,
                        title: pinHash.isEmpty ? "Set PIN" : "Change PIN",
                        subtitle: pinHash.isEmpty ? "Add a backup unlock method" : nil,
                        value: pinHash.isEmpty ? "Not set" : "Active"
                    )
                }
                .buttonStyle(.plain)

                if !pinHash.isEmpty {
                    SettingsDivider()

                    Button {
                        pinHash = ""
                        withAnimation { statusMessage = "PIN removed." }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { statusMessage = nil }
                        }
                    } label: {
                        SettingsActionRow(
                            icon: "lock.slash.fill",
                            iconColor: Color.ncDanger,
                            title: "Remove PIN",
                            titleColor: Color.ncDanger
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            SettingsCard {
                NavigationLink {
                    DataPrivacyView()
                } label: {
                    SettingsDisclosureRow(
                        icon: "hand.raised.fill",
                        iconColor: Color.ncPurple,
                        title: "Data & Privacy",
                        subtitle: "AI processing, exports, and advanced controls",
                        value: nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        SettingsSection(title: "APPEARANCE") {
            SettingsCard {
                NavigationLink {
                    ThemeProfileSettings(themeMode: $themeMode, focusReadingMode: $focusReadingMode)
                } label: {
                    SettingsDisclosureRow(
                        icon: "paintpalette.fill",
                        iconColor: Color.ncPurple,
                        title: "Theme",
                        subtitle: "Customize the look and feel",
                        value: themeMode
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        SettingsSection(title: "DATA MANAGEMENT") {
            SettingsCard {
                SettingsToggleRow(
                    icon: "icloud.fill",
                    iconColor: Color.ncPurple,
                    title: "iCloud Sync",
                    subtitle: "Back up meetings across your Apple devices. Audio files stay on this device.",
                    isOn: Binding(
                        get: { iCloudSyncEnabled },
                        set: { newValue in
                            iCloudSyncEnabled = newValue
                            showICloudRestartAlert = true
                        }
                    )
                )
            }

            SettingsCard {
                Button { createBackup() } label: {
                    SettingsDisclosureRow(
                        icon: "doc.text.fill",
                        iconColor: Color.ncSuccess,
                        title: backupURL == nil ? "Export JSON Backup" : "Backup Ready",
                        subtitle: "Download your data in JSON format",
                        value: nil
                    )
                }
                .buttonStyle(.plain)

                if let backupURL {
                    SettingsDivider()

                    ShareLink(item: backupURL) {
                        SettingsDisclosureRow(
                            icon: "square.and.arrow.up.fill",
                            iconColor: Color.ncPurple,
                            title: "Share Backup",
                            subtitle: nil,
                            value: nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Auto-delete
            SettingsCard {
                HStack(spacing: NCSpacing.md) {
                    SettingsIcon(icon: "clock.arrow.circlepath", color: Color.ncWarning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Delete Old Meetings")
                            .font(.ncHeadline)
                            .foregroundStyle(Color.ncInk)
                        Text(selfDestructDays == 0 ? "Disabled — meetings kept forever" : "Delete meetings older than \(selfDestructDays) days")
                            .font(.ncCaption1)
                            .foregroundStyle(Color.ncMuted)
                    }

                    Spacer()

                    Picker("", selection: $selfDestructDays) {
                        Text("Off").tag(0)
                        Text("30d").tag(30)
                        Text("90d").tag(90)
                        Text("180d").tag(180)
                        Text("1y").tag(365)
                    }
                    .pickerStyle(.menu)
                    .tint(Color.ncPurple)
                }
                .padding(.horizontal, NCSpacing.lg)
                .padding(.vertical, NCSpacing.md + 2)
            }

            // Danger zone
            SettingsCard {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack(spacing: NCSpacing.md) {
                        SettingsIcon(icon: "trash.fill", color: Color.ncDanger)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete All Data")
                                .font(.ncHeadline)
                                .foregroundStyle(Color.ncDanger)
                            Text("Permanently remove everything from this device")
                                .font(.ncCaption1)
                                .foregroundStyle(Color.ncMuted)
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

    // MARK: - Storage Section

    private var storageSection: some View {
        SettingsSection(title: "STORAGE") {
            SettingsCard {
                NavigationLink {
                    StorageManagementView()
                } label: {
                    SettingsDisclosureRow(
                        icon: "internaldrive.fill",
                        iconColor: Color(red: 0.31, green: 0.55, blue: 0.70),
                        title: "Storage",
                        subtitle: "Manage local files and space usage",
                        value: nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        SettingsSection(title: "BULK EXPORT") {
            SettingsCard {
                Button {
                    guard FreeLimitTracker.shared.canExport() else {
                        showPaywall = true
                        return
                    }
                    Task {
                        isExporting = true
                        defer { isExporting = false }
                        do {
                            bulkExportURL = try MeetingExportService.exportAll(allMeetings)
                            withAnimation { exportSuccess = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { exportSuccess = false }
                            }
                        } catch {
                            bulkExportError = error.localizedDescription
                            NoteCruxLog.export.debug("Bulk export failed: \(String(describing: error), privacy: .public)")
                        }
                    }
                } label: {
                    HStack(spacing: NCSpacing.md) {
                        SettingsIcon(
                            icon: "arrow.up.doc.on.clipboard",
                            color: Color(red: 0.04, green: 0.42, blue: 0.43)
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isExporting ? "Preparing archive..." : "Export All Meetings")
                                .font(.ncHeadline)
                                .foregroundStyle(Color.ncInk)
                            Text("Creates markdown files for each meeting")
                                .font(.ncCaption1)
                                .foregroundStyle(Color.ncMuted)
                        }

                        Spacer()

                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if exportSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.ncSuccess)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.ncMuted.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, NCSpacing.lg)
                    .padding(.vertical, NCSpacing.md + 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsRowPressStyle())
                .disabled(isExporting || allMeetings.isEmpty)
                .opacity(allMeetings.isEmpty ? 0.5 : 1)
            }
        }
    }

    // MARK: - Actions

    private func createBackup() {
        do {
            backupURL = try LocalBackupService.export(meetings: meetings, folders: folders, tasks: tasks)
            withAnimation { statusMessage = "Local JSON backup created." }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { statusMessage = nil }
            }
        } catch {
            withAnimation { statusMessage = "Backup failed: \(error.localizedDescription)" }
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
        withAnimation { statusMessage = "All local meeting data deleted." }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { statusMessage = nil }
        }
    }
}

// MARK: - Identity Header

private struct SettingsIdentityHeader: View {
    @State private var glowPulsing = false

    var body: some View {
        VStack(spacing: NCSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: NCSpacing.xs) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)

                    Text("Settings")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.ncInk)
                }

                Spacer()
            }

            // Identity card
            HStack(spacing: NCSpacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.ncPurple.opacity(0.08))
                        .frame(width: 72, height: 72)
                        .scaleEffect(glowPulsing ? 1.06 : 0.98)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.ncPurple, Color(red: 0.35, green: 0.25, blue: 0.90)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.ncPurple.opacity(0.2), radius: 12, y: 4)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: NCSpacing.sm) {
                    Text("NoteCrux User")
                        .font(.ncHeadline)
                        .foregroundStyle(Color.ncInk)

                    HStack(spacing: NCSpacing.xs) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("LOCAL ONLY")
                            .font(.ncCaption2)
                            .tracking(1.0)
                    }
                    .foregroundStyle(Color.ncPurple)
                    .padding(.horizontal, NCSpacing.sm + 2)
                    .padding(.vertical, NCSpacing.xs + 1)
                    .background(Color.ncPurple.opacity(0.08), in: Capsule())

                    Text("Your data stays on this device")
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)
                }

                Spacer()
            }
            .padding(NCSpacing.lg)
            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                    .strokeBorder(Color.ncDivider.opacity(0.3), lineWidth: 0.5)
            )
            .ncShadow(.card)
        }
        .padding(.top, NCSpacing.sm)
        .task {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowPulsing = true
            }
        }
    }
}

// MARK: - Section Wrapper

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpacing.md) {
            Text(title)
                .font(.ncOverline)
                .tracking(1.4)
                .foregroundStyle(Color.ncMuted)
                .padding(.horizontal, NCSpacing.xs)

            content
        }
    }
}

// MARK: - Card Container

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncDivider.opacity(0.3), lineWidth: 0.5)
        )
        .ncShadow(.card)
    }
}

// MARK: - Row Components

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            SettingsIcon(icon: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                Text(subtitle)
                    .font(.ncCaption1)
                    .foregroundStyle(Color.ncMuted)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.ncPurple)
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md + 2)
    }
}

struct SettingsDisclosureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    let value: String?

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            SettingsIcon(icon: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ncHeadline)
                    .foregroundStyle(Color.ncInk)

                if let subtitle {
                    Text(subtitle)
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncMuted)
                }
            }

            Spacer()

            if let value {
                Text(value)
                    .font(.ncCaption1.bold())
                    .foregroundStyle(Color.ncSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ncMuted.opacity(0.5))
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md + 2)
        .contentShape(Rectangle())
    }
}

private struct SettingsActionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var titleColor: Color = .ncInk

    var body: some View {
        HStack(spacing: NCSpacing.md) {
            SettingsIcon(icon: icon, color: iconColor)

            Text(title)
                .font(.ncHeadline)
                .foregroundStyle(titleColor)

            Spacer()
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md + 2)
        .contentShape(Rectangle())
    }
}

struct SettingsIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.10))
                .frame(width: 34, height: 34)

            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.ncDivider.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 62)
    }
}

// MARK: - Privacy Guarantee Card

private struct PrivacyGuaranteeCard: View {
    @State private var shieldGlow = false

    var body: some View {
        VStack(spacing: NCSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.ncPurple.opacity(0.06))
                    .frame(width: 56, height: 56)
                    .scaleEffect(shieldGlow ? 1.1 : 0.95)

                Image(systemName: "shield.checkered")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.ncPurple)
            }

            Text("Privacy Guarantee")
                .font(.ncHeadline)
                .foregroundStyle(Color.ncInk)

            Text("Your data never leaves this device. Ever.\nNoteCrux is local-first by design.")
                .font(.ncFootnote)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ncSecondary)

            Text("You're in full control of your data")
                .font(.ncCaption1.weight(.semibold))
                .foregroundStyle(Color.ncPurple)
                .padding(.top, NCSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NCSpacing.xxl)
        .padding(.horizontal, NCSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .fill(Color.ncSurface)
                .overlay(
                    LinearGradient(
                        colors: [Color.ncPurple.opacity(0.04), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncPurple.opacity(0.10), lineWidth: 1)
        )
        .ncShadow(.card)
        .task {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                shieldGlow = true
            }
        }
    }
}

// MARK: - Status Toast

private struct StatusToast: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: NCSpacing.sm) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSuccess ? Color.ncSuccess : Color.ncDanger)

            Text(message)
                .font(.ncFootnote.weight(.medium))
                .foregroundStyle(Color.ncInk)
        }
        .padding(.horizontal, NCSpacing.lg)
        .padding(.vertical, NCSpacing.md)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                .strokeBorder(Color.ncDivider.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Footer

private struct SettingsFooter: View {
    var body: some View {
        VStack(spacing: NCSpacing.xs) {
            HStack(spacing: NCSpacing.xs) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                Text("NoteCrux")
                    .font(.ncCaption2)
            }
            .foregroundStyle(Color.ncMuted.opacity(0.5))

            Text("Version 2.1 · Local-first privacy")
                .font(.ncOverline)
                .foregroundStyle(Color.ncMuted.opacity(0.4))
        }
        .padding(.top, NCSpacing.sm)
    }
}

// MARK: - Row Press Style

struct SettingsRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Sub-Screens

private struct ThemeProfileSettings: View {
    @Binding var themeMode: String
    @Binding var focusReadingMode: Bool

    var body: some View {
        ZStack {
            Color.ncBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: NCSpacing.xl) {
                    SettingsSection(title: "THEME") {
                        SettingsCard {
                            ForEach(["System", "Light", "Dark"], id: \.self) { mode in
                                Button {
                                    themeMode = mode
                                } label: {
                                    HStack(spacing: NCSpacing.md) {
                                        SettingsIcon(
                                            icon: mode == "System" ? "circle.lefthalf.filled" : mode == "Light" ? "sun.max.fill" : "moon.fill",
                                            color: Color.ncPurple
                                        )

                                        Text(mode)
                                            .font(.ncHeadline)
                                            .foregroundStyle(Color.ncInk)

                                        Spacer()

                                        if themeMode == mode {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Color.ncPurple)
                                        }
                                    }
                                    .padding(.horizontal, NCSpacing.lg)
                                    .padding(.vertical, NCSpacing.md + 2)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(SettingsRowPressStyle())

                                if mode != "Dark" {
                                    SettingsDivider()
                                }
                            }
                        }
                    }

                    SettingsSection(title: "READING") {
                        SettingsCard {
                            SettingsToggleRow(
                                icon: "doc.richtext",
                                iconColor: Color.ncSuccess,
                                title: "Focus Reading Mode",
                                subtitle: "Reduce distractions when reading notes",
                                isOn: $focusReadingMode
                            )
                        }
                    }
                }
                .padding(.horizontal, NCSpacing.lg + 2)
                .padding(.top, NCSpacing.md)
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PINSetupView: View {
    @Binding var pinHash: String
    @Binding var statusMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var error: String?
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var pinFocused: Bool

    var body: some View {
        ZStack {
            Color.ncBackground.ignoresSafeArea()

            VStack(spacing: NCSpacing.xxl) {
                VStack(spacing: NCSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.ncPurple.opacity(0.08))
                            .frame(width: 72, height: 72)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Color.ncPurple)
                    }

                    Text(pinHash.isEmpty ? "Set a PIN" : "Change PIN")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.ncInk)

                    Text("This PIN is a fallback when Face ID is unavailable.")
                        .font(.ncFootnote)
                        .foregroundStyle(Color.ncMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(.top, NCSpacing.xxxl)

                VStack(spacing: NCSpacing.lg) {
                    VStack(alignment: .leading, spacing: NCSpacing.sm) {
                        Text("NEW PIN")
                            .font(.ncOverline)
                            .tracking(1.4)
                            .foregroundStyle(Color.ncMuted)

                        SecureField("Enter PIN (min 4 digits)", text: $pin)
                            .keyboardType(.numberPad)
                            .textContentType(.newPassword)
                            .font(.ncBody)
                            .focused($pinFocused)
                            .padding(NCSpacing.md)
                            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                    .strokeBorder(error != nil ? Color.ncDanger.opacity(0.5) : Color.ncDivider.opacity(0.5), lineWidth: 1)
                            )
                            .offset(x: shakeOffset)
                    }

                    VStack(alignment: .leading, spacing: NCSpacing.sm) {
                        Text("CONFIRM PIN")
                            .font(.ncOverline)
                            .tracking(1.4)
                            .foregroundStyle(Color.ncMuted)

                        SecureField("Confirm PIN", text: $confirmPIN)
                            .keyboardType(.numberPad)
                            .textContentType(.newPassword)
                            .font(.ncBody)
                            .padding(NCSpacing.md)
                            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                    .strokeBorder(Color.ncDivider.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                .frame(maxWidth: 320)

                if let error {
                    HStack(spacing: NCSpacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(error)
                            .font(.ncCaption1.weight(.medium))
                    }
                    .foregroundStyle(Color.ncDanger)
                    .transition(.opacity)
                }

                Button(action: savePIN) {
                    Text("Save PIN")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 320)
                        .padding(.vertical, NCSpacing.md + 2)
                        .background(
                            LinearGradient(
                                colors: [Color.ncPurple, Color(red: 0.35, green: 0.25, blue: 0.90)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                        )
                        .shadow(color: Color.ncPurple.opacity(0.3), radius: 12, y: 4)
                }
                .buttonStyle(NCPressButtonStyle())
                .disabled(pin.count < 4)
                .opacity(pin.count < 4 ? 0.5 : 1)

                Spacer()
            }
            .padding(.horizontal, NCSpacing.xxl)
        }
        .navigationTitle("PIN Setup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pinFocused = true }
    }

    private func savePIN() {
        guard pin.count >= 4 else {
            error = "PIN must be at least 4 digits."
            shakeField()
            return
        }
        guard pin == confirmPIN else {
            error = "PINs don't match."
            shakeField()
            return
        }
        pinHash = AppSecurity.hashPIN(pin)
        statusMessage = "PIN saved."
        dismiss()
    }

    private func shakeField() {
        withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.08, dampingFraction: 0.2)) { shakeOffset = -10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { shakeOffset = 0 }
        }
    }
}

private struct BulkExportWrapper: Identifiable {
    let id = UUID()
    let url: URL
}
