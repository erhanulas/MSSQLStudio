// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MSSQLStudio", platforms: [.macOS("27.0")], products: [
    .library(name: "SQLServerKit", targets: ["SQLServerKit"]),
    .executable(name: "MSSQLStudio", targets: ["MSSQLStudio"])
], targets: [
    .systemLibrary(name: "CODBC", pkgConfig: "odbc", providers: [.brew(["unixodbc"])]),
    .systemLibrary(name: "CSQLite"),
    .target(name: "SQLTextCore"),
    .target(name: "SQLServerKit", dependencies: ["CODBC", "CSQLite", "SQLTextCore"], resources: [.process("Resources")]),
    .executableTarget(name: "MSSQLStudio", dependencies: ["SQLServerKit"]),
    .testTarget(name: "SQLTextCoreTests", dependencies: ["SQLTextCore"]),
    .testTarget(name: "SQLServerKitTests", dependencies: ["SQLServerKit"]),
    .testTarget(name: "StudioStateTests", dependencies: ["MSSQLStudio", "SQLServerKit"])
], swiftLanguageModes: [.v6])
