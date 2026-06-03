// swift-tools-version: 6.2
import PackageDescription

private let strictSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "FireAuthRelux",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FireAuthRelux", targets: ["FireAuthRelux"]),
    ],
    dependencies: [
        .package(url: "https://github.com/relux-works/FireAuthKit.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/relux-works/swift-relux.git", .upToNextMajor(from: "9.0.1")),
    ],
    targets: [
        .target(
            name: "FireAuthRelux",
            dependencies: [
                .product(name: "FireAuthKit", package: "FireAuthKit"),
                .product(name: "FireAuthProvider", package: "FireAuthKit"),
                .product(name: "Relux", package: "swift-relux"),
            ],
            path: "Sources/FireAuthRelux",
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "FireAuthReluxTests",
            dependencies: [
                "FireAuthRelux",
                .product(name: "FireAuthKit", package: "FireAuthKit"),
                .product(name: "FireAuthProvider", package: "FireAuthKit"),
                .product(name: "Relux", package: "swift-relux"),
            ],
            path: "Tests/FireAuthReluxTests",
            swiftSettings: strictSwiftSettings
        ),
    ]
)
