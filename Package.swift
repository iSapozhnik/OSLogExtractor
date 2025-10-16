// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OSLogExtractor",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "OSLogExtractor", targets: ["OSLogExtractor"])
    ],
    dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.6.0")
    ],
    targets: [
        .target(name: "OSLogExtractor", dependencies: ["ZipArchive"]),
        .testTarget(
            name: "OSLogExtractorTests",
            dependencies: ["OSLogExtractor"]
        )
    ]
)
