import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Manage") {
                    row(.today)
                    row(.plan)
                    row(.profile)
                }
                Section("Work") {
                    row(.releases)
                    row(.press)
                    row(.coverage)
                    row(.targets, badge: model.targetsDueCount)
                    row(.email)
                    row(.calendar)
                    row(.tasks)
                    row(.team)
                    row(.contacts)
                }
                Section("Control") {
                    row(.approvals, badge: model.pendingApprovalCount)
                    row(.integrations)
                    row(.roadmap)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) { updateFooter }
        } detail: {
            VStack(spacing: 0) {
                if let banner = model.banner {
                    BannerView(banner: banner, onUndo: { model.undo($0) }, onDismiss: { model.banner = nil })
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(existing: model.workspace)
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 600)
        }
    }

    private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(badge)
            .tag(item)
            .accessibilityLabel(badge > 0 ? "\(item.title), \(badge) waiting" : item.title)
    }

    @ViewBuilder private var detail: some View {
        switch model.selection ?? .today {
        case .today: TodayView()
        case .plan: PlanView()
        case .profile: ProfileView()
        case .releases: ReleasesView()
        case .press: PressView()
        case .coverage: CoverageView()
        case .targets: TargetsView()
        case .email: EmailListView()
        case .calendar: CalendarView()
        case .tasks: TasksView()
        case .team: ContactsView(audience: .team).id("team")
        case .contacts: ContactsView(audience: .contacts).id("contacts")
        case .approvals: ApprovalsView()
        case .integrations: IntegrationsView()
        case .roadmap: RoadmapView()
        }
    }

    private var updateFooter: some View {
        HStack {
            Text("Version \(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            CheckForUpdatesButton()
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
