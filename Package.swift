// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrettyMarkdown",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PrettyMarkdown", targets: ["PrettyMarkdown"])
    ],
    targets: [
        .executableTarget(
            name: "PrettyMarkdown",
            path: "Sources/PrettyMarkdown",
            resources: [.process("Resources")]
        )
    ]
)
