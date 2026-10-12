// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CheatSheetMini",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CheatSheetMini", targets: ["CheatSheetMini"])],
    dependencies: [
        .package(url: "https://github.com/johnxnguyen/Down.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "CheatSheetMini",
            dependencies: [.product(name: "Down", package: "Down")],
            resources: [.copy("Resources/StatusBarBirdBook.imageset")]
        )
    ]
)
