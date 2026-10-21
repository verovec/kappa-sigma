/// The one namespace of accessibility identifiers (card 0079): stable ids a test, a UI script or
/// 0061's first-stack guide resolves a control by.
///
/// Never derived from a title (titles change with the language): every id is built here from a
/// fixed name and, for a repeated control, the caller's stable key.
nonisolated package struct AccessibilityID: Hashable, Sendable, CustomStringConvertible {
  /// The identifier string (`fr.astrostack.parameter.haBlend.slider`).
  package let rawValue: String

  private init(_ path: String...) {
    rawValue = (["fr.astrostack"] + path).joined(separator: ".")
  }

  package var description: String { rawValue }

  /// A control inside a shared component.
  package enum Part: String, Sendable {
    /// Back to the default.
    case reset
    /// The slider of a parameter.
    case slider
    /// The typed field of a parameter.
    case field
    /// A tool's install link.
    case install
    /// A tool's « Re-check ».
    case recheck
    /// A curve's drawing surface.
    case canvas
  }

  // MARK: - Shared components

  /// A parameter row's `part` (`slider`, `field`, `reset`) for the parameter `key`.
  package static func parameter(_ key: String, _ part: Part) -> Self {
    Self("parameter", key, part.rawValue)
  }

  /// An install card's `part` (`install`, `recheck`) for `tool`.
  package static func installCard(_ tool: String, _ part: Part) -> Self {
    Self("install", tool.lowercased(), part.rawValue)
  }

  /// A curve editor's `part` (`canvas`, `reset`) for the curve `key`.
  package static func curve(_ key: String, _ part: Part) -> Self {
    Self("curve", key, part.rawValue)
  }

  // MARK: - Workspace

  /// The journey sidebar row of a stage (`JourneyStage.rawValue`).
  package static func journeyStage(_ stage: String) -> Self {
    Self("journey", stage)
  }

  /// A stage pane's control `name` in `stage`.
  package static func stageControl(_ stage: String, _ name: String) -> Self {
    Self("stage", stage, name)
  }

  /// The Données stage's « Import Captures… ».
  package static let importCaptures = stageControl("data", "import")

  /// The shortcuts sheet's search field.
  package static let shortcutsSearch = Self("shortcuts", "search")

  /// The glossary window's search field.
  package static let glossarySearch = Self("glossary", "search")

  /// An id for a test fixture only (`fr.astrostack.test.<name>`).
  package static func fixture(_ name: String) -> Self {
    Self("test", name)
  }
}
