import AppKit
import SwiftUI
import UserNotifications

/// Shows every outside service Manager touches, what's connected (nothing is, by default),
/// how each works today without a connection, and what the app may do on its own.
struct IntegrationsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(UpdateController.self) private var updates
    @State private var notificationStatus = "Checking…"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Connections", subtitle: "What Manager connects to, what it's allowed to do, and how each service works without a connection.")
                accountsCard
                permissionsCard
                ForEach(IntegrationCatalog.all) { info in
                    IntegrationCard(info: info)
                }
            }
            .padding(24)
        }
        .task { await refreshNotificationStatus() }
    }

    private var accountsCard: some View {
        Card("Connected accounts", symbol: "person.badge.key") {
            Text("This version doesn't sign in to any outside account. It never sends email, posts, pays or signs anything. Your data stays in one file on this Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            LabeledContent("Software updates") {
                if let url = updates.repositoryURL {
                    Link(url.absoluteString.replacingOccurrences(of: "https://", with: ""), destination: url)
                } else {
                    Text("Not configured in this build")
                }
            }
            LabeledContent("GitHub token") {
                Text(updates.hasToken ? "Saved in your Keychain" : "None (not needed: the repository is public)")
            }
            LabeledContent("Notifications") { Text(notificationStatus) }
            LabeledContent("Data folder") {
                Text(model.persistence.rootURL.path).font(.caption.monospaced()).textSelection(.enabled)
            }
            HStack {
                SettingsLink { Text("Open Settings…") }
                Button("Show Data in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.persistence.workspaceURL])
                }
            }
        }
    }

    private var permissionsCard: some View {
        let policy = model.workspace.permissions
        return Card("What Manager may do on its own", symbol: "checkmark.shield") {
            Toggle("Routine work is on", isOn: Binding(
                get: { model.workspace.settings.automationEnabled },
                set: { on in model.perform(on ? "Turned on routine work" : "Turned off routine work", showUndo: true) { $0.settings.automationEnabled = on } }))
            ForEach(ActionKind.allCases.filter(\.isConfigurable)) { kind in
                HStack {
                    Text(kind.label)
                    Spacer()
                    permissionBadge(policy.mode(for: kind))
                }
                .accessibilityElement(children: .combine)
            }
            Divider()
            Text("Always asks you first, and can't be changed:").font(.callout.weight(.medium))
            Text(ActionKind.allCases.filter(\.alwaysRequiresApproval).map(\.label).joined(separator: " · "))
                .font(.callout).foregroundStyle(.secondary)
            SettingsLink { Text("Change Permissions…") }
        }
    }

    private func permissionBadge(_ mode: PermissionMode) -> StatusBadge {
        switch mode {
        case .automatic: return StatusBadge(text: mode.label, tone: .success, symbol: "bolt")
        case .askFirst: return StatusBadge(text: mode.label, tone: .warning, symbol: "hand.raised")
        case .off: return StatusBadge(text: mode.label, tone: .neutral, symbol: "slash.circle")
        }
    }

    private func refreshNotificationStatus() async {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else {
            notificationStatus = "Available in the packaged app"
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: notificationStatus = "Allowed"
        case .denied: notificationStatus = "Turned off in System Settings › Notifications"
        case .notDetermined: notificationStatus = "Not asked yet"
        default: notificationStatus = "Unknown"
        }
    }
}

private struct IntegrationCard: View {
    @EnvironmentObject var model: AppModel
    var info: IntegrationInfo

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: info.symbol).foregroundStyle(.secondary).frame(width: 22)
                Text(info.name).font(.headline)
                Spacer()
                badge
            }
            LabeledText(label: "Used for", value: info.usedFor)
            LabeledText(label: "How it works now", value: info.howItWorksNow)
            if !info.formats.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Formats").foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                    ChipList(items: info.formats)
                }
            }
            if !info.requires.isBlank {
                LabeledText(label: info.status == .builtIn ? "Optional" : "To connect", value: info.requires)
            }
            if let destination = info.destination {
                Button("Go to \(SidebarItem(destination).title)") { model.open(destination) }.buttonStyle(.link)
            }
        }
    }

    private var badge: StatusBadge {
        switch info.status {
        case .builtIn: return StatusBadge(text: info.status.label, tone: .success, symbol: "checkmark.circle")
        case .manual: return StatusBadge(text: info.status.label, tone: .info, symbol: "arrow.up.arrow.down")
        case .notConnected: return StatusBadge(text: info.status.label, tone: .neutral, symbol: "link.badge.plus")
        }
    }
}

// MARK: - Roadmap

struct RoadmapView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Coming Next", subtitle: "What works today in each area, what's planned, and what needs an outside service.")
                Text("Live shows, finances, sync and marketing already have a foothold through the calendar, contacts, outreach and budgets. These are the next steps for each area.")
                    .foregroundStyle(.secondary)
                ForEach(Roadmap.areas) { area in
                    Card(area.title, symbol: area.symbol) {
                        HStack(alignment: .top, spacing: 20) {
                            column("Works today", area.availableNow, symbol: "checkmark.circle.fill", tint: .green)
                            column("Planned", area.next, symbol: "circle.dashed", tint: .blue)
                            if !area.needsExternalService.isEmpty {
                                column("Needs an outside service", area.needsExternalService, symbol: "link", tint: .secondary)
                                    .frame(maxWidth: 220)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func column(_ title: String, _ items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(items, id: \.self) { item in
                Label {
                    Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(tint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
