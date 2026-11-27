import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Reviews, articles, interviews, premieres, radio, podcasts, video, playlist adds and mentions, in one place.
struct CoverageView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var kindFilter: KindFilter = .all
    @State private var show: Show = .all
    @State private var editing: CoverageDraft?
    @State private var addingLinks = false
    @State private var importing: IdentifiedPreview?
    @State private var checking = false

    enum KindFilter: Hashable, Identifiable {
        case all
        case kind(CoverageKind)
        var id: String { if case .kind(let k) = self { return k.rawValue } else { return "all" } }
    }

    enum Show: String, CaseIterable, Identifiable {
        case all, pressKit, needsQuote, notChecked, broken
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Everything"
            case .pressKit: return "In press kit"
            case .needsQuote: return "No pull quote yet"
            case .notChecked: return "Link not checked"
            case .broken: return "Link broken"
            }
        }
        func includes(_ c: Coverage) -> Bool {
            switch self {
            case .all: return true
            case .pressKit: return c.includeInPressKit
            case .needsQuote: return c.quote.isBlank && c.kind != .playlistAdd
            case .notChecked: return !c.url.isBlank && c.linkCheckedAt == nil && !c.verified
            case .broken: return !c.linkIssue.isBlank
            }
        }
    }

    private var all: [Coverage] { model.workspace.coverage }

    private var items: [Coverage] {
        all.filter { c in
            if case .kind(let k) = kindFilter, c.kind != k { return false }
            guard show.includes(c) else { return false }
            guard !search.isBlank else { return true }
            let release = model.workspace.release(c.releaseID)?.title ?? ""
            return [c.outlet, c.title, c.author, c.quote, c.excerpt, c.notes, c.url, release, c.kind.label]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
        .sorted { ($0.date ?? $0.addedAt ?? .distantPast) > ($1.date ?? $1.addedAt ?? .distantPast) }
    }

    private var summary: String {
        let counts = Dictionary(grouping: all, by: \.kind).mapValues(\.count)
        return CoverageKind.allCases.compactMap { k in
            guard let n = counts[k], n > 0 else { return nil }
            return "\(n) \(n == 1 ? k.label.lowercased() : k.pluralLabel)"
        }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Coverage").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        addMenu
                    }
                    HStack {
                        fileMenu
                        Button {
                            checkLinks(items.map(\.id))
                        } label: {
                            if checking { ProgressView().controlSize(.small) } else { Label("Check Links", systemImage: "link") }
                        }
                        .help("Open each link shown and note any that no longer work")
                        .disabled(checking || !items.contains { !$0.url.isBlank })
                    }
                    .controlSize(.small)
                    TextField("Search outlet, headline, writer, quote", text: $search).textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("Type", selection: $kindFilter) {
                            Text("All types").tag(KindFilter.all)
                            Divider()
                            ForEach(CoverageKind.allCases) { Text($0.label).tag(KindFilter.kind($0)) }
                        }
                        Picker("Show", selection: $show) {
                            ForEach(Show.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    .labelsHidden()
                    if !summary.isEmpty {
                        Text(summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                List(selection: $selectedID) {
                    ForEach(items) { c in
                        CoverageListRow(coverage: c).tag(c.id)
                            .contextMenu {
                                Button("Edit…") { editing = CoverageDraft(coverage: c, keepCopy: false) }
                                if let url = webURL(c.url) { Button("Open Link") { NSWorkspace.shared.open(url) } }
                                if let copy = c.savedCopy { Button("Open Saved Copy") { model.openCoverageFile(copy) } }
                                if !c.quote.isBlank { Button("Copy Quote with Credit") { Clipboard.copy("“\(c.quote)” — \(c.citation)") } }
                                Divider()
                                Button("Delete", role: .destructive) { delete(c) }
                            }
                    }
                }
                .overlay {
                    if !all.isEmpty && items.isEmpty {
                        Text("Nothing matches these filters.").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 330)
            Divider()
            detail
        }
        .sheet(item: $editing) { draft in
            CoverageEditor(draft: draft) { saved in selectedID = saved }.environmentObject(model)
        }
        .sheet(isPresented: $addingLinks) {
            AddCoverageLinksSheet { ids in selectedID = ids.first }.environmentObject(model)
        }
        .sheet(item: $importing) { item in
            CoverageImportSheet(preview: item.preview, fileName: item.fileName).environmentObject(model)
        }
        .onAppear {
            if let focus = model.focusedRecordID, all.contains(where: { $0.id == focus }) {
                selectedID = focus
                model.focusedRecordID = nil
            } else if selectedID == nil {
                selectedID = items.first?.id
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = selectedID, let c = all.first(where: { $0.id == id }) {
            CoverageDetail(coverage: c, onEdit: { editing = CoverageDraft(coverage: c, keepCopy: false) },
                           onDelete: { delete(c) }, onCheck: { checkLinks([c.id]) }, checking: checking)
                .id(c.id)
        } else if all.isEmpty {
            ContentUnavailableView {
                Label("No coverage saved yet", systemImage: "quote.bubble")
            } description: {
                Text("Keep every review, article, interview, premiere, radio play, podcast, video and mention here. Paste a link and Manager fills in the outlet, headline, writer, date and score, and can keep a copy of the page in case the link breaks. Print clippings and PDFs can be attached as files.")
            } actions: {
                Button("Add from a Link…") { addFromLink() }.buttonStyle(.borderedProminent)
                Button("Add Several Links…") { addingLinks = true }
                Button("Import a CSV File…") { importCSV() }
            }
        } else {
            EmptyStateView(title: "Choose a piece", symbol: "quote.bubble", message: "Select coverage on the left.")
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Add from a Link…") { addFromLink() }
            Button("Add Several Links…") { addingLinks = true }
            Divider()
            Button("Add a File (PDF, Scan or Screenshot)…") { addFromFiles() }
            Button("Add by Hand…") { editing = model.newCoverageDraft() }
        } label: {
            Image(systemName: "plus")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add coverage")
        .accessibilityLabel("Add coverage")
    }

    private var fileMenu: some View {
        Menu {
            Button("Import a CSV File…") { importCSV() }
            Button("Export as CSV…") {
                model.exportText(model.exportCoverageCSV(), suggestedName: "Coverage.csv", types: [.commaSeparatedText], logTitle: "Exported coverage")
            }
            .disabled(all.isEmpty)
        } label: {
            Label("Import / Export", systemImage: "square.and.arrow.up.on.square")
        }
        .fixedSize()
    }

    // MARK: Actions

    private func addFromLink() {
        var draft = model.newCoverageDraft()
        draft.coverage.date = nil
        if let link = Clipboard.text().flatMap({ CoverageLinks.extractURLs(from: $0).first }),
           !CoverageLinks.existingKeys(all).contains(CoverageLinks.normalize(link)) {
            draft.coverage.url = link
        }
        editing = draft
    }

    private func addFromFiles() {
        let urls = FilePanels.openFiles(types: [.pdf, .image, .audio, .movie, .plainText, .rtf, .html, .data],
                                        message: "Choose a clipping, PDF, screenshot or recording to keep with this coverage")
        guard !urls.isEmpty else { return }
        var draft = model.newCoverageDraft(kind: .article)
        draft.coverage.date = nil
        draft.coverage.title = (urls[0].lastPathComponent as NSString).deletingPathExtension
        model.addCoverageAttachments(from: urls, to: &draft.coverage)
        editing = draft
    }

    private func importCSV() {
        guard let url = FilePanels.openFile(types: [.commaSeparatedText, .plainText], message: "Choose a CSV of coverage") else { return }
        do {
            let text = try FilePanels.readText(url)
            importing = IdentifiedPreview(preview: CoverageCSV.preview(csv: text, existing: all, releases: model.workspace.releases),
                                          fileName: url.lastPathComponent)
        } catch {
            model.showError("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func checkLinks(_ ids: [UUID]) {
        checking = true
        Task {
            let result = await model.checkCoverageLinks(ids)
            checking = false
            if result.checked == 0 { return }
            if !result.broken.isEmpty {
                model.showError("\(result.broken.count) link\(result.broken.count == 1 ? "" : "s") no longer work\(result.broken.count == 1 ? "s" : ""): \(result.broken.prefix(3).joined(separator: "; ")). Saved copies are still here.")
            } else if !result.unreachable.isEmpty {
                model.showInfo("\(result.working) of \(result.checked) links work. \(result.unreachable.count) couldn't be checked (the site was unreachable or refused) — try again later.")
            } else {
                model.banner = Banner(style: .success, message: result.checked == 1 ? "The link works." : "All \(result.checked) links work.")
            }
        }
    }

    private func delete(_ c: Coverage) {
        model.perform("Deleted coverage: \(c.headline)", showUndo: true) { $0.remove(c.id, from: \.coverage) }
        if selectedID == c.id { selectedID = nil }
    }
}

private struct IdentifiedPreview: Identifiable {
    let id = UUID()
    var preview: CoverageImportPreview
    var fileName: String
}

func webURL(_ raw: String) -> URL? {
    guard let url = URL(string: raw.trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
    return url
}

// MARK: - List row

private struct CoverageListRow: View {
    @EnvironmentObject var model: AppModel
    var coverage: Coverage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: coverage.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(coverage.outlet.isBlank ? "Unknown outlet" : coverage.outlet).fontWeight(.medium).lineLimit(1)
                if !coverage.title.isBlank { Text(coverage.title).font(.callout).lineLimit(2) }
                Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    if !coverage.linkIssue.isBlank { StatusBadge(text: "Link broken", tone: .critical, symbol: "exclamationmark.triangle") }
                    if coverage.includeInPressKit { StatusBadge(text: "Press kit", tone: .info, symbol: "newspaper") }
                    if coverage.savedCopy != nil || !coverage.attachments.isEmpty {
                        Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Has a saved copy or files")
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        [coverage.kind.label, coverage.date?.shortDate ?? "", coverage.rating].filter { !$0.isBlank }.joined(separator: " · ")
    }
}

// MARK: - Detail

private struct CoverageDetail: View {
    @EnvironmentObject var model: AppModel
    var coverage: Coverage
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onCheck: () -> Void
    var checking: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                if !coverage.quote.isBlank || coverage.kind != .playlistAdd { quoteCard }
                if !coverage.excerpt.isBlank {
                    Card("Summary", symbol: "text.alignleft") {
                        Text(coverage.excerpt).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                filesCard
                connectionsCard
                if !coverage.notes.isBlank {
                    Card("Notes", symbol: "note.text") {
                        Text(coverage.notes).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Spacer()
                    Button("Delete Coverage", role: .destructive, action: onDelete)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(coverage.kind.label, systemImage: coverage.kind.symbol).font(.callout).foregroundStyle(.secondary)
            Text(coverage.outlet.isBlank ? "Unknown outlet" : coverage.outlet).font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if !coverage.title.isBlank { Text(coverage.title).font(.title3).textSelection(.enabled) }
            let byline = [coverage.author.isBlank ? "" : "By \(coverage.author)", coverage.date?.shortDate ?? "",
                          coverage.rating.isBlank ? "" : "Score: \(coverage.rating)"].filter { !$0.isBlank }
            if !byline.isEmpty { Text(byline.joined(separator: " · ")).foregroundStyle(.secondary) }
            HStack(spacing: 6) {
                linkBadge
                if coverage.includeInPressKit { StatusBadge(text: "In press kit", tone: .info, symbol: "newspaper") }
            }
        }
    }

    @ViewBuilder private var linkBadge: some View {
        if coverage.url.isBlank {
            StatusBadge(text: "No link", tone: .neutral, symbol: "link")
        } else if !coverage.linkIssue.isBlank {
            StatusBadge(text: coverage.linkIssue, tone: .critical, symbol: "exclamationmark.triangle")
        } else if let checked = coverage.linkCheckedAt, coverage.verified {
            StatusBadge(text: "Link worked \(checked.shortDate)", tone: .success, symbol: "checkmark.seal")
        } else if coverage.verified {
            StatusBadge(text: "You confirmed the link", tone: .success, symbol: "checkmark.seal")
        } else {
            StatusBadge(text: "Link not checked", tone: .neutral, symbol: "questionmark.circle")
        }
    }

    private var actions: some View {
        HStack {
            Button("Edit…", action: onEdit).keyboardShortcut("e", modifiers: .command)
            if let url = webURL(coverage.url) {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open Link", systemImage: "arrow.up.right.square") }
                Button(action: onCheck) {
                    if checking { ProgressView().controlSize(.small) } else { Label("Check Link", systemImage: "arrow.clockwise") }
                }
                .disabled(checking)
                .help("Open the link and note whether the page is still there")
            }
            if let copy = coverage.savedCopy {
                Button { model.openCoverageFile(copy) } label: { Label("Saved Copy", systemImage: "doc.text") }
                    .help("Open the copy of the page Manager kept")
            }
            Button {
                let c = coverage
                model.perform(c.includeInPressKit ? "Removed from press kit: \(c.headline)" : "Added to press kit: \(c.headline)", showUndo: true) { ws in
                    if let i = ws.coverage.firstIndex(where: { $0.id == c.id }) { ws.coverage[i].includeInPressKit.toggle() }
                }
            } label: {
                Label(coverage.includeInPressKit ? "Remove from Press Kit" : "Add to Press Kit", systemImage: "newspaper")
            }
        }
    }

    private var quoteCard: some View {
        Card("Pull quote", symbol: "quote.opening") {
            if coverage.quote.isBlank {
                Text("No pull quote yet. Choose a line from the piece to show in your press kit and pitches.")
                    .foregroundStyle(.secondary)
                Button("Add a Quote…", action: onEdit)
            } else {
                Text("“\(coverage.quote)”").font(.title3).italic().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("— \(coverage.citation)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy with Credit") { Clipboard.copy("“\(coverage.quote)” — \(coverage.citation)") }.controlSize(.small)
                }
            }
        }
    }

    private var filesCard: some View {
        Card("Saved copy & files", symbol: "paperclip") {
            if let copy = coverage.savedCopy {
                fileRow(name: "Copy of the page", detail: coverage.addedAt.map { "Saved \($0.shortDate)" } ?? "", file: copy, symbol: "doc.richtext")
            }
            ForEach(coverage.attachments) { a in
                fileRow(name: a.originalName.isBlank ? "Attachment" : a.originalName, detail: "", file: a.fileName, symbol: "doc")
            }
            if coverage.savedCopy == nil && coverage.attachments.isEmpty {
                Text(coverage.url.isBlank
                     ? "Attach a PDF, a scan of a print clipping, a screenshot or a recording."
                     : "No copy saved. Edit and use Look Up to keep a copy of the page, or attach a PDF or screenshot.")
                    .foregroundStyle(.secondary)
            }
            Button {
                let urls = FilePanels.openFiles(types: [.pdf, .image, .audio, .movie, .plainText, .rtf, .html, .data],
                                                message: "Choose files to keep with this coverage")
                guard !urls.isEmpty else { return }
                var updated = coverage
                model.addCoverageAttachments(from: urls, to: &updated)
                guard updated.attachments.count > coverage.attachments.count else { return }
                model.perform("Attached \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files") to \(updated.headline)", showUndo: true) { ws in
                    ws.upsert(updated, in: \.coverage)
                }
            } label: {
                Label("Attach Files…", systemImage: "plus")
            }
            .controlSize(.small)
        }
    }

    private func fileRow(name: String, detail: String, file: String, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(name)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                if !model.persistence.mediaFileExists(file) { Text("File missing").font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            Button("Open") { model.openCoverageFile(file) }.controlSize(.small)
            Button("Show in Finder") { model.revealCoverageFile(file) }.controlSize(.small)
        }
    }

    private var connectionsCard: some View {
        Card("Connected to", symbol: "link") {
            LabeledText(label: "Release", value: model.workspace.release(coverage.releaseID)?.title ?? "")
            LabeledText(label: "Writer or host", value: model.workspace.contact(coverage.contactID)?.displayName ?? coverage.author)
            if !coverage.url.isBlank { LabeledText(label: "Link", value: coverage.url) }
            if let added = coverage.addedAt { LabeledText(label: "Added", value: added.shortDate) }
            HStack {
                if let release = coverage.releaseID, model.workspace.release(release) != nil {
                    Button("Open Release") { model.open(.releases, record: release) }.controlSize(.small)
                }
                if let contact = coverage.contactID, model.workspace.contact(contact) != nil {
                    Button("Open Contact") { model.open(.contacts, record: contact) }.controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Editor

/// Adds or edits one piece of coverage. With a link, Look Up reads the page and fills in what it can.
struct CoverageEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: CoverageDraft
    var onSaved: (UUID) -> Void = { _ in }
    @State private var lookingUp = false
    @State private var kindChosen = false
    @State private var lookedUpURL = ""

    private var c: Coverage { draft.coverage }
    private var exists: Bool { model.workspace.coverage.contains { $0.id == c.id } }
    private var duplicate: Coverage? {
        guard !c.url.isBlank else { return nil }
        let key = CoverageLinks.normalize(c.url)
        return model.workspace.coverage.first { $0.id != c.id && !$0.url.isBlank && CoverageLinks.normalize($0.url) == key }
    }
    private var canLookUp: Bool {
        !lookingUp && !c.url.isBlank && CoverageLinks.normalize(c.url) != CoverageLinks.normalize(lookedUpURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("Link", text: $draft.coverage.url, prompt: Text("Paste a link to the review, article, episode or video"))
                            .onSubmit { if canLookUp { lookUp() } }
                        Button {
                            lookUp()
                        } label: {
                            if lookingUp { ProgressView().controlSize(.small) } else { Text("Look Up") }
                        }
                        .disabled(!canLookUp)
                        .help("Read the page and fill in the details")
                    }
                    if let problem = draft.problem {
                        Label("Couldn't read the page: \(problem) Fill in the details yourself, or open the link to check it.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.callout)
                    } else if lookingUp {
                        Text("Reading the page…").font(.callout).foregroundStyle(.secondary)
                    } else if draft.snapshot != nil || draft.document != nil {
                        Label("Filled in from the page. Check the details before saving.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green).font(.callout)
                    }
                    if let duplicate {
                        Label("Already saved: \(duplicate.headline)", systemImage: "doc.on.doc").foregroundStyle(.orange).font(.callout)
                    }
                }
                Section("The piece") {
                    Picker("Type", selection: Binding(get: { c.kind }, set: { draft.coverage.kind = $0; kindChosen = true })) {
                        ForEach(CoverageKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    TextField(c.kind == .playlistAdd ? "Playlist" : c.kind == .radioPlay ? "Station or show" : "Outlet", text: $draft.coverage.outlet)
                    TextField(c.kind == .playlistAdd ? "Song added" : "Headline or title", text: $draft.coverage.title)
                    TextField(c.kind == .playlistAdd ? "Curator" : (c.kind == .podcast || c.kind == .radioPlay) ? "Host" : "Writer", text: $draft.coverage.author)
                    OptionalDatePicker(title: c.kind == .radioPlay ? "Aired" : "Published", date: $draft.coverage.date)
                    if c.kind == .review || !c.rating.isBlank {
                        TextField("Score", text: $draft.coverage.rating, prompt: Text("e.g. 8/10 or 4 stars"))
                    }
                }
                Section {
                    TextField("Pull quote", text: $draft.coverage.quote, prompt: Text("The line you'd put in your press kit"), axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Summary", text: $draft.coverage.excerpt, axis: .vertical).lineLimit(2...6)
                    TextField("Notes", text: $draft.coverage.notes, prompt: Text("Print run, page number, who arranged it…"), axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Words")
                } footer: {
                    Text("Quote the piece exactly as published, and credit the outlet when you use it.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Connections") {
                    ReleasePicker(selection: $draft.coverage.releaseID)
                    ContactPicker(title: "Writer or curator contact", selection: $draft.coverage.contactID)
                    Toggle("Show in my press kit", isOn: $draft.coverage.includeInPressKit)
                    Toggle("I've opened the link and the piece is live", isOn: $draft.coverage.verified)
                        .disabled(c.url.isBlank)
                }
                Section("Saved copy & files") {
                    if draft.snapshot != nil, c.savedCopy == nil {
                        Toggle("Keep a copy of the page in case the link breaks", isOn: $draft.keepCopy)
                    }
                    if c.savedCopy != nil {
                        Label("Copy of the page saved", systemImage: "doc.richtext")
                    }
                    if let doc = draft.document {
                        Label("\(doc.name) will be kept with this coverage", systemImage: "doc")
                    }
                    ForEach(c.attachments) { a in
                        HStack {
                            Label(a.originalName.isBlank ? "Attachment" : a.originalName, systemImage: "doc")
                            Spacer()
                            Button("Remove") { draft.coverage.attachments.removeAll { $0.id == a.id } }.controlSize(.small)
                        }
                    }
                    Button("Attach Files…") {
                        let urls = FilePanels.openFiles(types: [.pdf, .image, .audio, .movie, .plainText, .rtf, .html, .data],
                                                        message: "Choose files to keep with this coverage")
                        model.addCoverageAttachments(from: urls, to: &draft.coverage)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Delete", role: .destructive) {
                        let item = c
                        model.perform("Deleted coverage: \(item.headline)", showUndo: true) { $0.remove(item.id, from: \.coverage) }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(exists ? "Save" : "Add Coverage") {
                    var toSave = draft
                    if toSave.coverage.addedAt == nil { toSave.coverage.addedAt = Date() }
                    let saved = model.saveCoverage(toSave)
                    onSaved(saved.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(c.outlet.isBlank && c.title.isBlank)
            }
            .padding()
        }
        .frame(width: 600, height: 720)
        .onAppear {
            kindChosen = exists
            if !exists, !c.url.isBlank, draft.snapshot == nil, draft.problem == nil { lookUp() }
        }
    }

    private func lookUp() {
        let link = c.url
        lookingUp = true
        Task {
            let found = await model.lookUpCoverage(link)
            lookingUp = false
            lookedUpURL = link
            merge(found)
        }
    }

    /// Fills blanks from what the page says. Anything the artist already typed stays.
    private func merge(_ found: CoverageDraft) {
        let f = found.coverage
        var current = draft.coverage
        if found.problem == nil { current.url = f.url }
        if current.outlet.isBlank { current.outlet = f.outlet }
        if current.title.isBlank { current.title = f.title }
        if current.author.isBlank { current.author = f.author }
        if current.date == nil { current.date = f.date }
        if current.rating.isBlank { current.rating = f.rating }
        if current.excerpt.isBlank { current.excerpt = f.excerpt }
        if current.releaseID == nil { current.releaseID = f.releaseID }
        if current.contactID == nil { current.contactID = f.contactID }
        if !kindChosen {
            current.kind = f.kind
            current.includeInPressKit = f.includeInPressKit
        }
        current.linkCheckedAt = f.linkCheckedAt ?? current.linkCheckedAt
        current.linkIssue = f.linkIssue
        if found.problem == nil { current.verified = true }
        draft.coverage = current
        draft.problem = found.problem
        draft.snapshot = found.snapshot ?? draft.snapshot
        draft.document = found.document ?? draft.document
        if found.snapshot != nil && current.savedCopy == nil { draft.keepCopy = true }
    }
}

// MARK: - Several links at once

private struct AddCoverageLinksSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var onAdded: ([UUID]) -> Void

    @State private var text = ""
    @State private var drafts: [CoverageDraft] = []
    @State private var include = Set<UUID>()
    @State private var reading = false
    @State private var progress = 0
    @State private var total = 0
    @State private var alreadySaved: [String] = []
    @State private var keepCopies = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add several links").font(.title2.weight(.semibold))
            Text("Paste links, or a whole email or document that contains them. Manager opens each page once, fills in the details, and you choose what to keep. Nothing is posted or sent.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if drafts.isEmpty && !reading {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                    .accessibilityLabel("Links to add")
                let found = CoverageLinks.extractURLs(from: text)
                Text(found.isEmpty ? "No links found yet." : "\(found.count) link\(found.count == 1 ? "" : "s") found.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if reading {
                ProgressView(value: Double(progress), total: Double(max(total, 1))) {
                    Text("Reading page \(min(progress + 1, total)) of \(total)…")
                }
                Spacer()
            } else {
                if !alreadySaved.isEmpty {
                    Text("\(alreadySaved.count) already saved and skipped.").font(.callout).foregroundStyle(.secondary)
                }
                List {
                    ForEach($drafts) { $draft in
                        HStack(alignment: .top) {
                            Toggle("", isOn: Binding(
                                get: { include.contains(draft.id) },
                                set: { on in if on { include.insert(draft.id) } else { include.remove(draft.id) } }))
                                .labelsHidden()
                                .accessibilityLabel("Add \(draft.coverage.headline)")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.coverage.outlet.isBlank ? "Unknown outlet" : draft.coverage.outlet).fontWeight(.medium)
                                Text(draft.coverage.title.isBlank ? draft.coverage.url : draft.coverage.title).font(.callout).lineLimit(2)
                                Text([draft.coverage.author, draft.coverage.date?.shortDate ?? "", draft.coverage.rating].filter { !$0.isBlank }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let problem = draft.problem {
                                    Label("Couldn't read the page: \(problem)", systemImage: "exclamationmark.triangle")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Picker("Type", selection: $draft.coverage.kind) {
                                ForEach(CoverageKind.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Toggle("Keep a copy of each page in case links break", isOn: $keepCopies)
            }
            HStack {
                if !drafts.isEmpty {
                    Button("Start Over") { drafts = []; include = []; alreadySaved = [] }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if drafts.isEmpty {
                    Button("Read Pages") { read() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(reading || CoverageLinks.extractURLs(from: text).isEmpty)
                } else {
                    Button("Add \(include.count) Piece\(include.count == 1 ? "" : "s")") {
                        let chosen = drafts.filter { include.contains($0.id) }.map { d -> CoverageDraft in
                            var d = d
                            d.keepCopy = keepCopies
                            return d
                        }
                        model.saveCoverageBatch(chosen)
                        onAdded(chosen.map(\.id))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(include.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: 620)
    }

    private func read() {
        let existing = CoverageLinks.existingKeys(model.workspace.coverage)
        let links = CoverageLinks.extractURLs(from: text)
        alreadySaved = links.filter { existing.contains(CoverageLinks.normalize($0)) }
        let toRead = links.filter { !existing.contains(CoverageLinks.normalize($0)) }
        guard !toRead.isEmpty else {
            model.showInfo("Every link there is already saved.")
            dismiss()
            return
        }
        total = toRead.count
        progress = 0
        reading = true
        Task {
            var results: [CoverageDraft] = []
            for link in toRead {
                results.append(await model.lookUpCoverage(link))
                progress += 1
            }
            drafts = results
            include = Set(results.map(\.id))
            reading = false
        }
    }
}

// MARK: - CSV import

private struct CoverageImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var preview: CoverageImportPreview
    var fileName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import coverage").font(.title2.weight(.semibold))
            Text("\(fileName): \(preview.totalRows) row\(preview.totalRows == 1 ? "" : "s"). Columns Manager understands include date, outlet, title, type, url, author, rating, quote, excerpt, notes and release.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Label("\(preview.added.count) to add", systemImage: "plus.circle")
                Label("\(preview.duplicates.count) already saved", systemImage: "doc.on.doc")
                Label("\(preview.skipped.count) skipped", systemImage: "minus.circle")
            }
            List {
                if !preview.added.isEmpty {
                    Section("To add") {
                        ForEach(preview.added) { c in
                            VStack(alignment: .leading) {
                                Text(c.headline)
                                Text([c.kind.label, c.date?.shortDate ?? "", c.author].filter { !$0.isBlank }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !preview.duplicates.isEmpty || !preview.skipped.isEmpty {
                    Section("Not imported") {
                        ForEach(preview.duplicates + preview.skipped, id: \.self) { Text($0).font(.callout) }
                    }
                }
            }
            Text("Imported links haven't been opened yet, so they're marked not checked. Use Check Links afterwards.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import \(preview.added.count)") {
                    model.importCoverage(preview, fileName: fileName)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!preview.hasChanges)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
    }
}
