import AstroStackApp
import ProcessKit
import Testing

/// Layer-aware rows (card 0135): a line's parameters show only when its layer is in the bundle,
/// or when the current values still ask for that layer (so a screen on by default can be
/// switched off); a process without layer rows hides nothing.
extension ProcessPanelModelTests {
  struct Visibility: CustomTestStringConvertible, Sendable {
    let name: String
    let processID: String
    let layers: Set<String>
    /// Values set before looking, by parameter id.
    var values: [String: ParamValue] = [:]
    /// Prefixes of the parameter ids that must be visible, and those that must be hidden.
    let visible: [String]
    let hidden: [String]
    var testDescription: String { name }
  }

  nonisolated static let visibilities: [Visibility] = [
    Visibility(
      name: "screens on a BB + Hα + OIII stack: no SII row", processID: EmissionScreensProcess.id,
      layers: ["RGB", "Ha", "OIII"], visible: ["ha", "oiii", "nbBlend"], hidden: ["sii"]),
    Visibility(
      name: "injection on a BB + Hα + OIII stack: no SII row", processID: LineInjectionProcess.id,
      layers: ["RGB", "Ha", "OIII"], visible: ["ha", "oiii"], hidden: ["sii"]),
    Visibility(
      name: "injection: a gain with every share at 0 keeps the rows (the gain is the switch)",
      processID: LineInjectionProcess.id, layers: ["RGB", "Ha", "OIII"],
      values: [
        "siiGain": .number(1), "siiRed": .number(0), "siiGreen": .number(0),
        "siiBlue": .number(0),
      ], visible: ["ha", "oiii", "sii"], hidden: []),
    Visibility(
      name: "screens on a broadband-only stack: the lines on by default stay, to be switched off",
      processID: EmissionScreensProcess.id, layers: ["RGB"], visible: ["ha", "oiii"],
      hidden: ["sii"]),
    Visibility(
      name: "screens on a broadband-only stack, every line off: no line row",
      processID: EmissionScreensProcess.id, layers: ["RGB"],
      values: ["haEnabled": .flag(false), "oiiiEnabled": .flag(false)], visible: ["nbBlend"],
      hidden: ["ha", "oiii", "sii"]),
    Visibility(
      name: "every line in the stack: every row", processID: EmissionScreensProcess.id,
      layers: ["RGB", "Ha", "OIII", "SII"], visible: ["ha", "oiii", "sii"], hidden: []),
    Visibility(
      name: "a process without layer rows hides nothing", processID: StretchProcess.id,
      layers: ["RGB"], visible: [], hidden: []),
  ]

  @Test("testVisibleSpecs: a line's rows only when its layer exists", arguments: visibilities)
  func testVisibleSpecs(row: Visibility) throws {
    let type = try #require(ProcessRegistry.standard().type(id: row.processID))
    let panel = ProcessPanelModel(type: type, params: ParamSet(schema: type.schema))
    panel.showsAdvanced = true
    for (id, value) in row.values { panel.set(id, value) }
    panel.layerIDs = row.layers
    let ids = panel.visibleSpecs.map(\.id)
    for prefix in row.visible {
      #expect(ids.contains { $0.hasPrefix(prefix) }, "\(prefix) rows must show")
    }
    for prefix in row.hidden {
      #expect(!ids.contains { $0.hasPrefix(prefix) }, "\(prefix) rows must hide")
    }
    if row.hidden.isEmpty && row.visible.isEmpty {
      #expect(ids.count == type.schema.specs.count)
    }
  }
}
