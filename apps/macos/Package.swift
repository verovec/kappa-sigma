// swift-tools-version: 6.2
// AstroStack 2 — the source of truth for every module (CLAUDE.md, swift-conventions.md).
// Module boundaries are pinned by `testModuleBoundary` in every test target against the
// allow-list in Tests/TestSupport/ModuleBoundary.swift. Keep each target a single
// `.target(name: "…", dependencies: [...])` call with literal names: that test reads this file.
import PackageDescription

/// Settings shared by every target (playbook §1–§2).
let common: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .treatAllWarnings(as: .error),
  .treatWarning("DeprecatedDeclaration", as: .warning),
]
/// Kits with few pointers also opt into strict memory safety (SE-0458).
let safe: [SwiftSetting] = common + [.strictMemorySafety()]
/// Only the app target defaults to the main actor; the kits stay nonisolated.
let app: [SwiftSetting] = common + [.defaultIsolation(MainActor.self)]

let package = Package(
  name: "AstroStack",
  defaultLocalization: "en",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "AstroStackApp", targets: ["AstroStackApp"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.2"),
  ],
  targets: [
    .target(
      name: "ImageKit", dependencies: [],
      exclude: ["README.md"], swiftSettings: common),
    .target(
      name: "RenderKit", dependencies: ["ImageKit"],
      exclude: ["README.md"], resources: [.copy("Shaders")], swiftSettings: common),
    .target(
      name: "ProcessKit", dependencies: ["ImageKit", "RenderKit"],
      exclude: ["README.md"], swiftSettings: safe),
    .target(
      name: "ProjectKit", dependencies: ["ImageKit", .product(name: "GRDB", package: "GRDB.swift")],
      exclude: ["README.md", "SCHEMA.md"], resources: [.copy("Migrations")],
      swiftSettings: safe),
    .target(
      name: "StackKit",
      dependencies: [
        "ImageKit", "ProjectKit", .product(name: "Subprocess", package: "swift-subprocess"),
      ],
      exclude: ["README.md", "Siril/README.md", "Inspect/README.md", "Calibration/README.md",
        "Preprocess/README.md",
      ], swiftSettings: common),
    .target(
      name: "HelpKit", dependencies: [],
      exclude: ["README.md"], resources: [.copy("Help")], swiftSettings: safe),
    .executableTarget(
      name: "AstroStackApp",
      dependencies: ["ImageKit", "RenderKit", "ProcessKit", "ProjectKit", "StackKit", "HelpKit"],
      swiftSettings: app),

    .target(
      name: "TestSupport", dependencies: [],
      path: "Tests/TestSupport", swiftSettings: common),
    .testTarget(
      name: "TestSupportTests", dependencies: ["TestSupport"],
      resources: [.copy("Fixtures")], swiftSettings: common),
    .testTarget(
      name: "ImageKitTests", dependencies: ["ImageKit", "TestSupport"],
      resources: [.copy("Fixtures")], swiftSettings: common),
    .testTarget(
      name: "RenderKitTests", dependencies: ["RenderKit", "TestSupport"],
      swiftSettings: common),
    .testTarget(
      name: "ProcessKitTests",
      dependencies: ["ProcessKit", "ImageKit", "HelpKit", "TestSupport"],
      resources: [.copy("Fixtures")], swiftSettings: common),
    .testTarget(
      name: "ProjectKitTests",
      dependencies: ["ProjectKit", "TestSupport", .product(name: "GRDB", package: "GRDB.swift")],
      swiftSettings: common),
    .testTarget(
      name: "StackKitTests", dependencies: ["StackKit", "ImageKit", "ProjectKit", "TestSupport"],
      resources: [.copy("Fixtures")], swiftSettings: common),
    .testTarget(
      name: "HelpKitTests", dependencies: ["HelpKit", "TestSupport"],
      swiftSettings: common),
    .testTarget(
      name: "AstroStackAppTests",
      dependencies: ["AstroStackApp", "ImageKit", "ProjectKit", "RenderKit", "TestSupport"],
      swiftSettings: common),
  ]
)
