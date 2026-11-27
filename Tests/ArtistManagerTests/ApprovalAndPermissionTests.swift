import XCTest
@testable import ArtistManager

final class ApprovalAndPermissionTests: XCTestCase {
    // MARK: Permissions

    func testExternalAndBindingActionsAlwaysAskFirst() {
        var policy = PermissionPolicy()
        for kind in ActionKind.allCases where kind.alwaysRequiresApproval {
            policy.set(.automatic, for: kind)
            policy.modes[kind.rawValue] = .automatic // even if the stored file says otherwise
            XCTAssertEqual(policy.mode(for: kind), .askFirst, "\(kind) must always ask first")
        }
    }

    func testRequiredApprovalsCoverEverythingTheSpecNames() {
        let required: Set<ActionKind> = [.sendExternalMessage, .sendPressOutreach, .sendEmailCampaign, .publishContent,
                                         .acceptOffer, .spendMoney, .contractualCommitment]
        XCTAssertEqual(Set(ActionKind.allCases.filter(\.alwaysRequiresApproval)), required)
        XCTAssertTrue(required.allSatisfy { !$0.isConfigurable })
    }

    func testRoutineActionsAreConfigurable() {
        var policy = PermissionPolicy()
        XCTAssertEqual(policy.mode(for: .createTasks), .automatic)
        XCTAssertEqual(policy.mode(for: .sendPreApprovedReminders), .askFirst, "Reminders default to asking first")
        policy.set(.off, for: .createTasks)
        XCTAssertEqual(policy.mode(for: .createTasks), .off)
    }

    // MARK: Outreach approval

    func testApprovingOutreachMarksItReadyButNotSent() {
        var ws = Workspace.onboarded()
        let contact = makeContact("Ana", email: "ana@example.com")
        ws.contacts = [contact]
        let item = Outreach(kind: .press, contactID: contact.id, subject: "Hello", body: "Body")
        ws.outreach = [item]

        let request = ApprovalService.requestForOutreach(item, in: &ws)
        XCTAssertEqual(ws.outreach[0].status, .awaitingApproval)
        XCTAssertEqual(request.kind, .sendPressOutreach)
        XCTAssertTrue(request.preview.contains("ana@example.com"), "The preview shows exactly who it goes to")
        XCTAssertTrue(request.preview.contains("Body"))

        ApprovalService.approve(request.id, in: &ws, now: TestDates.now)
        XCTAssertEqual(ws.outreach[0].status, .approved)
        XCTAssertNil(ws.outreach[0].sentAt, "Approval never records a send")
        XCTAssertEqual(ws.approvals[0].state, .approved)
    }

    func testDecliningReturnsToDraft() {
        var ws = Workspace.onboarded()
        let item = Outreach(kind: .booking, subject: "Dates?", body: "Hi")
        ws.outreach = [item]
        let request = ApprovalService.requestForOutreach(item, in: &ws)
        ApprovalService.decline(request.id, note: "Not now", in: &ws)
        XCTAssertEqual(ws.outreach[0].status, .draft)
        XCTAssertEqual(ws.approvals[0].state, .declined)
        XCTAssertEqual(ws.approvals[0].decisionNote, "Not now")
    }

    func testAskingAgainSupersedesThePendingRequest() {
        var ws = Workspace.onboarded()
        let item = Outreach(kind: .press, subject: "v1", body: "Hi")
        ws.outreach = [item]
        let first = ApprovalService.requestForOutreach(item, in: &ws)
        let second = ApprovalService.requestForOutreach(item, in: &ws)
        XCTAssertEqual(ws.approvals.first { $0.id == first.id }?.state, .superseded)
        XCTAssertEqual(ws.approvals.first { $0.id == second.id }?.state, .pending)
        XCTAssertEqual(ws.pendingApprovals.count, 1)
    }

    func testDecidingTwiceHasNoEffect() {
        var ws = Workspace.onboarded()
        let item = Outreach(kind: .press, subject: "s", body: "b")
        ws.outreach = [item]
        let request = ApprovalService.requestForOutreach(item, in: &ws)
        ApprovalService.decline(request.id, in: &ws)
        ApprovalService.approve(request.id, in: &ws)
        XCTAssertEqual(ws.approvals[0].state, .declined)
        XCTAssertEqual(ws.outreach[0].status, .draft)
    }

    // MARK: Campaigns and spending

    func testCampaignApprovalRecordsRecipientCountAndNeverSends() {
        var ws = Workspace.onboarded()
        ws.subscribers = [Subscriber(email: "a@example.com"), Subscriber(email: "b@example.com", status: .unsubscribed)]
        let campaign = EmailCampaign(subject: "New single", body: "Listen. Unsubscribe anytime.")
        ws.campaigns = [campaign]
        let request = ApprovalService.requestForCampaign(campaign, in: &ws)
        XCTAssertTrue(request.title.contains("1 subscriber"), "Only subscribed addresses count: \(request.title)")
        ApprovalService.approve(request.id, in: &ws)
        XCTAssertEqual(ws.campaigns[0].status, .approved)
        XCTAssertEqual(ws.campaigns[0].approvedRecipientCount, 1)
        XCTAssertNil(ws.campaigns[0].sentAt)
    }

    func testSpendApprovalDoesNotMarkPaid() {
        var ws = Workspace.onboarded()
        let line = BudgetLine(category: .mastering, title: "Mastering", planned: 300)
        ws.budgetLines = [line]
        let request = ApprovalService.requestForSpend(line, currency: "USD", in: &ws)
        XCTAssertEqual(ws.budgetLines[0].status, .awaitingApproval)
        XCTAssertTrue(request.title.contains("300"))
        ApprovalService.approve(request.id, in: &ws)
        XCTAssertEqual(ws.budgetLines[0].status, .approved)
        XCTAssertEqual(ws.budgetLines[0].actual, 0)
    }

    // MARK: Automation suggestions

    func testApprovingReminderSuggestionApprovesThoseReminders() {
        var ws = Workspace.onboarded()
        ws.permissions.set(.askFirst, for: .sendPreApprovedReminders)
        let drummer = makeContact("Sam", email: "sam@example.com", role: .musician, team: true)
        ws.contacts = [drummer]
        var show = CalendarEvent(title: "The Earl", kind: .show, start: TestDates.now.adding(days: 1), end: TestDates.now.adding(days: 1).adding(hours: 2))
        show.contactIDs = [drummer.id]
        ws.events = [show]

        let items = AutomationEngine.plan(for: ws, now: TestDates.now).filter { $0.kind == .sendPreApprovedReminders }
        XCTAssertEqual(items.count, 1)
        let request = ApprovalService.requestForAutomation(items[0])
        XCTAssertTrue(request.preview.contains("Subject:"), "Reminder bodies are shown before approval")
        ws.approvals.append(request)
        ApprovalService.approve(request.id, in: &ws, now: TestDates.now)

        let reminder = try? XCTUnwrap(ws.outreach.first { $0.kind == .reminder })
        XCTAssertEqual(reminder?.status, .approved)
        XCTAssertNil(reminder?.sentAt, "Still not sent — the artist sends it")
    }

    func testAutomaticRemindersAreMarkedApprovedByRule() {
        var ws = Workspace.onboarded()
        ws.permissions.set(.automatic, for: .sendPreApprovedReminders)
        let engineer = makeContact("Lee", email: "lee@example.com", role: .engineer)
        ws.contacts = [engineer]
        var session = CalendarEvent(title: "Mix session", kind: .studio, start: TestDates.now.adding(days: 2), end: TestDates.now.adding(days: 2).adding(hours: 4))
        session.contactIDs = [engineer.id]
        ws.events = [session]
        let item = try! XCTUnwrap(AutomationEngine.plan(for: ws, now: TestDates.now).first { $0.kind == .sendPreApprovedReminders })
        XCTAssertEqual(item.proposal.outreach.first?.status, .approved)
        XCTAssertNotNil(item.proposal.outreach.first?.approvedByRule)
    }

    func testRemindersOffProducesNothing() {
        var ws = Workspace.onboarded()
        ws.permissions.set(.off, for: .sendPreApprovedReminders)
        let c = makeContact("Lee", email: "lee@example.com", role: .engineer)
        ws.contacts = [c]
        var e = CalendarEvent(title: "Rehearsal", kind: .rehearsal, start: TestDates.now.adding(days: 1), end: TestDates.now.adding(days: 1))
        e.contactIDs = [c.id]
        ws.events = [e]
        XCTAssertFalse(AutomationEngine.plan(for: ws, now: TestDates.now).contains { $0.kind == .sendPreApprovedReminders })
    }
}
