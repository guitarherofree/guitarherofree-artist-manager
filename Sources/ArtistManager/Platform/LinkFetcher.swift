import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads a coverage link the way a browser would, so Manager can fill in the details and keep a copy.
/// Only runs when the artist adds or checks a link; nothing is fetched in the background.
enum LinkFetcher {
    struct Page {
        var finalURL: String
        var data: Data
        var contentType: String
        var isHTML: Bool { contentType.isEmpty || contentType.contains("html") || contentType.contains("xml") }
        var html: String { LinkReader.decodeText(data, contentType: contentType) }
    }

    enum FetchError: LocalizedError {
        case badAddress
        case http(Int)
        case tooLarge
        case network(String)

        var errorDescription: String? {
            switch self {
            case .badAddress: return "That isn't a web address Manager can open."
            case .http(404), .http(410): return "Page not found (\(code))"
            case .http(401), .http(403): return "The site wouldn't show the page to Manager (\(code)). It may need a sign-in or block apps."
            case .http(429): return "The site asked Manager to slow down (429). Try again later."
            case .http(let status) where status >= 500: return "The site had a problem (\(status))."
            case .http(let status): return "The site answered with an error (\(status))."
            case .tooLarge: return "The page is too large to read."
            case .network(let message): return message
            }
        }

        private var code: Int { if case .http(let c) = self { return c } else { return 0 } }

        /// A missing page is a broken link; a refusal or a slow site says nothing about whether the piece is still up.
        var meansLinkIsBroken: Bool {
            if case .http(let status) = self { return status == 404 || status == 410 }
            return false
        }
    }

    static let maxBytes = 8_000_000

    static func fetch(_ raw: String) async throws -> Page {
        var text = raw.trimmed
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw FetchError.badAddress
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw FetchError.network("No response from the site.") }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
        guard data.count <= maxBytes else { throw FetchError.tooLarge }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        return Page(finalURL: http.url?.absoluteString ?? url.absoluteString, data: data, contentType: type)
    }
}
