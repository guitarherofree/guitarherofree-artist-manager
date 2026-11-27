import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Images from the media folder

struct MediaThumbnail: View {
    var url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: url) { image = NSImage(contentsOf: url) }
    }
}

// MARK: - A text document the artist can copy or save

struct TextDocumentSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var title: String
    var note: String = ""
    var fileName: String
    @State var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            if !note.isEmpty {
                Text(note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 300)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .accessibilityLabel(title)
            HStack {
                Button("Copy") { Clipboard.copy(text) }
                Button("Save as Text…") {
                    model.exportText(text, suggestedName: fileName, types: [.plainText], logTitle: "Saved \(title.lowercased())")
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 660, height: 580)
    }
}

// MARK: - Pickers

struct ContactPicker: View {
    @EnvironmentObject var model: AppModel
    var title: String
    @Binding var selection: UUID?
    var roles: [ContactRole]? = nil

    private var contacts: [Contact] {
        model.workspace.contacts
            .filter { contact in roles.map { $0.contains(contact.role) || contact.id == selection } ?? true }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag(UUID?.none)
            ForEach(contacts) { contact in
                Text(contact.organization.isBlank || contact.name.isBlank ? contact.displayName : "\(contact.name) — \(contact.organization)")
                    .tag(Optional(contact.id))
            }
        }
    }
}

struct ReleasePicker: View {
    @EnvironmentObject var model: AppModel
    var title: String = "Release"
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag(UUID?.none)
            ForEach(model.workspace.releases) { release in
                Text(release.title.isBlank ? "Untitled release" : release.title).tag(Optional(release.id))
            }
        }
    }
}

// MARK: - Contact and media-list import

struct ContactImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var fileName = ""
    @State private var text = ""
    @State private var role: ContactRole
    @State private var tags: [String]
    @State private var markAsTeam = false
    private let title: String
    private let vCard: Bool

    init(title: String = "Import Contacts", defaultRole: ContactRole = .other, defaultTags: [String] = [], vCard: Bool = false) {
        self.title = title
        self.vCard = vCard
        _role = State(initialValue: defaultRole)
        _tags = State(initialValue: defaultTags)
    }

    private var isVCardFile: Bool { fileName.lowercased().hasSuffix(".vcf") || fileName.lowercased().hasSuffix(".vcard") }

    private var preview: ContactImportPreview? {
        guard !text.isEmpty else { return nil }
        if isVCardFile {
            return VCard.preview(vcf: text, existing: model.workspace.contacts, defaultRole: role, tagsToAdd: tags, markAsTeam: markAsTeam)
        }
        return ContactCSV.preview(csv: text, existing: model.workspace.contacts, defaultRole: role, tagsToAdd: tags, markAsTeam: markAsTeam)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.semibold))
            Text(vCard
                 ? "Choose a vCard (.vcf) file. In Contacts, select people and choose File › Export › Export vCard. Google Contacts and Outlook export vCards too. Existing contacts are only filled in, never overwritten."
                 : "Choose a CSV from a spreadsheet, a PR database or a curator list. Columns like Name, Email, Company/Outlet/Playlist, Role, Phone and Tags are recognized. Existing contacts are only filled in, never overwritten.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(vCard ? "Choose vCard File…" : "Choose CSV File…") { choose() }
                Text(fileName.isEmpty ? "No file chosen" : fileName).foregroundStyle(.secondary)
            }
            Form {
                Picker(isVCardFile ? "Role when a title doesn't say" : "Role for rows without one", selection: $role) {
                    ForEach(ContactRole.allCases) { Text($0.label).tag($0) }
                }
                TagsField(title: "Add tags", values: $tags)
                Toggle("Mark everyone in this file as part of my team", isOn: $markAsTeam)
            }
            .formStyle(.grouped)
            .frame(height: 170)
            if let preview {
                GroupBox("What will happen") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(preview.totalRows) \(isVCardFile ? "cards" : "rows") read")
                        Label("\(preview.added.count) new contacts", systemImage: "plus.circle")
                        Label("\(preview.updated.count) existing contacts filled in", systemImage: "arrow.triangle.merge")
                        if !preview.skipped.isEmpty {
                            DisclosureGroup("\(preview.skipped.count) rows skipped") {
                                ForEach(preview.skipped.prefix(50), id: \.self) { Text($0).font(.caption) }
                            }
                        }
                        if !preview.recognizedColumns.isEmpty {
                            Text("Columns used: \(preview.recognizedColumns.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    if let preview { model.importContacts(preview, fileName: fileName) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!(preview?.hasChanges ?? false))
            }
        }
        .padding(20)
        .frame(width: 600, height: 600)
    }

    private func choose() {
        let types: [UTType] = vCard ? [.vCard] : [.commaSeparatedText, .plainText, .vCard]
        guard let url = FilePanels.openFile(types: types, message: vCard ? "Choose a vCard file" : "Choose a contacts CSV file") else { return }
        do {
            text = try FilePanels.readText(url)
            fileName = url.lastPathComponent
        } catch {
            model.showError("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

// MARK: - Small helpers

struct ChipList: View {
    var items: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}

/// A segmented picker that sits under a page header.
struct SectionPicker<Value: Hashable & Identifiable>: View {
    var options: [Value]
    @Binding var selection: Value
    var label: (Value) -> String

    var body: some View {
        Picker("Section", selection: $selection) {
            ForEach(options) { option in Text(label(option)).tag(option) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
