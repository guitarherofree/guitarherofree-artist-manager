// swift-tools-version:5.9
import PackageDescription

// On macOS this builds the Manager app (SwiftUI + AppKit) with the standard GitHub Releases updater.
// On Linux it builds only the Foundation-based core under the same module name, so `swift test`
// exercises the same business logic on both.

#if os(macOS)
let dependencies: [Package.Dependency] = [.package(path: "Packages/GitHubReleaseUpdater")]
let appTarget: Target = .executableTarget(
    name: "ArtistManager",
    dependencies: [.product(name: "GitHubReleaseUpdater", package: "GitHubReleaseUpdater")],
    path: "Sources/ArtistManager"
)
let products: [Product] = [.executable(name: "ArtistManager", targets: ["ArtistManager"])]
#else
let dependencies: [Package.Dependency] = []
let appTarget: Target = .target(
    name: "ArtistManager",
    path: "Sources/ArtistManager",
    exclude: ["App", "Views", "Updates", "Platform"]
)
let products: [Product] = [.library(name: "ArtistManager", targets: ["ArtistManager"])]
#endif

let package = Package(
    name: "ArtistManager",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: [
        appTarget,
        .testTarget(
            name: "ArtistManagerTests",
            dependencies: ["ArtistManager"],
            path: "Tests/ArtistManagerTests"
        )
    ]
)
