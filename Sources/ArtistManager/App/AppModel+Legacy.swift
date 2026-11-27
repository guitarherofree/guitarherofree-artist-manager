import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    func saveLegacyPlan(_ plan: LegacyPlan, title: String = "Updated your legacy plan") {
        perform(title, showUndo: true) { $0.legacy = plan }
    }

    /// Writes the legacy letter to a temporary page and opens it in the browser, ready to print or save as PDF.
    func previewLegacyLetter() {
        let html = LegacyLetter.html(for: workspace)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeFileName(workspace.profile.displayName)) Legacy Plan.html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            showError("Couldn't open the letter: \(error.localizedDescription)")
        }
    }

    func exportLegacyLetter(markdown: Bool) {
        let name = "\(safeFileName(workspace.profile.displayName)) Legacy Plan"
        if markdown {
            exportText(LegacyLetter.markdown(for: workspace), suggestedName: name + ".md",
                       types: [.plainText], logTitle: "Exported your legacy plan")
        } else {
            exportText(LegacyLetter.html(for: workspace), suggestedName: name + ".html",
                       types: [.html], logTitle: "Exported your legacy plan")
        }
    }
}
