import Foundation

/// The running app's name and version, read from its Info.plist.
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Manager"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var versionString: String { "\(version) (\(build))" }
}
