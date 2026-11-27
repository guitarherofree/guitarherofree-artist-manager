import AppKit
import SwiftUI

// MARK: - Status badges (always icon + words, never color alone)

struct StatusBadge: View {
    enum Tone { case neutral, info, success, warning, critical, draft }
    var text: String
    var tone: Tone = .neutral
    var symbol: String?

    var color: Color {
        switch tone {
        case .neutral: return .secondary
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .critical: return .red
        case .draft: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}

extension OutreachStatus {
    var badge: StatusBadge {
        switch self {
        case .draft: return StatusBadge(text: label, tone: .draft, symbol: "pencil")
        case .awaitingApproval: return StatusBadge(text: label, tone: .warning, symbol: "hourglass")
        case .approved: return StatusBadge(text: label, tone: .info, symbol: "checkmark.shield")
        case .sent: return StatusBadge(text: label, tone: .success, symbol: "paperplane")
        case .replied: return StatusBadge(text: label, tone: .success, symbol: "arrowshape.turn.up.left")
        case .covered: return StatusBadge(text: label, tone: .success, symbol: "star")
        case .declined: return StatusBadge(text: label, tone: .neutral, symbol: "xmark")
        case .noResponse: return StatusBadge(text: label, tone: .neutral, symbol: "minus.circle")
        }
    }
}

extension CampaignStatus {
    var badge: StatusBadge {
        switch self {
        case .draft: return StatusBadge(text: label, tone: .draft, symbol: "pencil")
        case .awaitingApproval: return StatusBadge(text: label, tone: .warning, symbol: "hourglass")
        case .approved: return StatusBadge(text: label, tone: .info, symbol: "checkmark.shield")
        case .exported: return StatusBadge(text: label, tone: .info, symbol: "square.and.arrow.up")
        case .sent: return StatusBadge(text: label, tone: .success, symbol: "paperplane")
        case .cancelled: return StatusBadge(text: label, tone: .neutral, symbol: "xmark")
        }
    }
}

extension SubscriptionStatus {
    var badge: StatusBadge {
        switch self {
        case .subscribed: return StatusBadge(text: label, tone: .success, symbol: "checkmark.circle")
        case .pending: return StatusBadge(text: label, tone: .warning, symbol: "hourglass")
        case .unsubscribed: return StatusBadge(text: label, tone: .neutral, symbol: "minus.circle")
        case .bounced: return StatusBadge(text: label, tone: .critical, symbol: "exclamationmark.triangle")
        case .complained: return StatusBadge(text: label, tone: .critical, symbol: "hand.raised")
        case .cleaned: return StatusBadge(text: label, tone: .neutral, symbol: "trash")
        }
    }
}

extension ApprovalState {
    var badge: StatusBadge {
        switch self {
        case .pending: return StatusBadge(text: label, tone: .warning, symbol: "hourglass")
        case .approved: return StatusBadge(text: label, tone: .success, symbol: "checkmark")
        case .declined: return StatusBadge(text: label, tone: .neutral, symbol: "xmark")
        case .superseded: return StatusBadge(text: label, tone: .neutral, symbol: "arrow.triangle.2.circlepath")
        }
    }
}

extension ActionStatus {
    var badge: StatusBadge {
        switch self {
        case .completed: return StatusBadge(text: label, tone: .success, symbol: "checkmark")
        case .drafted: return StatusBadge(text: label, tone: .draft, symbol: "pencil")
        case .recommended: return StatusBadge(text: label, tone: .info, symbol: "lightbulb")
        case .awaitingApproval: return StatusBadge(text: label, tone: .warning, symbol: "hourglass")
        case .approved: return StatusBadge(text: label, tone: .success, symbol: "checkmark.shield")
        case .declined: return StatusBadge(text: label, tone: .neutral, symbol: "xmark")
        case .undone: return StatusBadge(text: label, tone: .neutral, symbol: "arrow.uturn.backward")
        case .failed: return StatusBadge(text: label, tone: .critical, symbol: "exclamationmark.triangle")
        }
    }
}

extension Priority {
    var badge: StatusBadge {
        switch self {
        case .high: return StatusBadge(text: "High priority", tone: .critical, symbol: "exclamationmark")
        case .normal: return StatusBadge(text: "Normal", tone: .neutral)
        case .low: return StatusBadge(text: "Low", tone: .neutral)
        }
    }
}

// MARK: - Layout helpers

struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String = "", @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.bottom, 8)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String = "") {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, symbol: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let symbol { Image(systemName: symbol) }
                }
                .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

struct EmptyStateView: View {
    var title: String
    var symbol: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
    }
}

struct BannerView: View {
    var banner: Banner
    var onUndo: (UUID) -> Void
    var onDismiss: () -> Void

    var symbol: String {
        switch banner.style {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    var tint: Color {
        switch banner.style {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(banner.message).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            if let undoID = banner.undoRecordID {
                Button("Undo") { onUndo(undoID) }
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss message")
        }
        .padding(10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}

/// A date picker for an optional date, with a toggle to clear it.
struct OptionalDatePicker: View {
    var title: String
    @Binding var date: Date?
    var components: DatePickerComponents = .date

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { on in date = on ? (date ?? Date().startOfDay) : nil }))
            if date != nil {
                DatePicker(title, selection: Binding(get: { date ?? Date() }, set: { date = $0 }), displayedComponents: components)
                    .labelsHidden()
            }
        }
    }
}

/// Edits a [String] as a comma-separated text field.
struct TagsField: View {
    var title: String
    @Binding var values: [String]
    var prompt: String = "Separate with commas"

    var body: some View {
        TextField(title, text: Binding(get: { values.commaJoined }, set: { values = $0.commaSeparatedValues }), prompt: Text(prompt))
    }
}

/// A currency text field bound to a Double.
struct MoneyField: View {
    var title: String
    @Binding var value: Double
    var currency: String

    var body: some View {
        TextField(title, value: $value, format: .currency(code: currency.isBlank ? "USD" : currency))
    }
}

struct LabeledText: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Text(value.isBlank ? "—" : value).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Date {
    var shortDate: String { formatted(date: .abbreviated, time: .omitted) }
    var shortDateTime: String { formatted(date: .abbreviated, time: .shortened) }

    var relativeDayText: String {
        let days = Date.daysBetween(Date(), self)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return formatted(.dateTime.weekday(.wide))
        default: return shortDate
        }
    }
}

/// Confirms an external action that the app can't do itself, e.g. "I sent this".
struct ConfirmSentButton: View {
    var title: String
    var explanation: String
    var action: () -> Void
    @State private var confirming = false

    var body: some View {
        Button(title) { confirming = true }
            .confirmationDialog(title, isPresented: $confirming) {
                Button(title, action: action)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(explanation)
            }
    }
}
