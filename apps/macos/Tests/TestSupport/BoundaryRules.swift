/// The allow-list a module's dependencies and imports are checked against.
package struct BoundaryRules: Sendable {
  /// For each module, the targets and products it may depend on. A module absent here fails.
  package let allowedDependencies: [String: Set<String>]
  /// Modules allowed to import a UI framework (SwiftUI, AppKit).
  package let uiModules: Set<String>
  /// The app target: no module may depend on it.
  package let appModule: String

  /// Creates rules; `appModule` defaults to the AstroStack app target.
  package init(
    allowedDependencies: [String: Set<String>], uiModules: Set<String>,
    appModule: String = "AstroStackApp"
  ) {
    self.allowedDependencies = allowedDependencies
    self.uiModules = uiModules
    self.appModule = appModule
  }

  /// AstroStack's module graph (swift-conventions.md "Structure", design §4.1). Widening an
  /// entry is a design decision: change it here, in the same PR as `Package.swift`.
  package static let astroStack = Self(
    allowedDependencies: [
      "ImageKit": [],
      "RenderKit": ["ImageKit"],
      "ProcessKit": ["ImageKit", "RenderKit"],
      "ProjectKit": ["ImageKit", "GRDB"],
      "StackKit": ["ImageKit", "ProjectKit"],
      "HelpKit": [],
      "AstroStackApp": [
        "ImageKit", "RenderKit", "ProcessKit", "ProjectKit", "StackKit", "HelpKit",
      ],
    ],
    uiModules: ["AstroStackApp", "RenderKit"]
  )
}
