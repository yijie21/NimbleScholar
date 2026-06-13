// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NimbleScholarCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NimbleScholarCore", targets: ["NimbleScholarCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0"),
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.16.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "NimbleScholarCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FlyingFox", package: "FlyingFox"),
                "SwiftSoup",
            ]
        ),
        .testTarget(
            name: "NimbleScholarCoreTests",
            dependencies: ["NimbleScholarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
