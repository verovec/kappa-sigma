import AstroStackApp
import Foundation
import ProcessKit
import Testing

/// The process panel is generated from the schema (card 0087): every kind of parameter gets its
/// identified control, advanced ones wait for the disclosure, suggestions are listed and never
/// applied, and the process card is there.
@MainActor
@Suite("ProcessPanel — rendered from the schema")
struct ProcessPanelTests {
  /// The id a spec's control reports.
  static func id(_ processID: String, _ spec: ParamSpec) -> String {
    let key = "\(processID).\(spec.id)"
    switch spec.kind {
    case .number: return "fr.astrostack.parameter.\(key).slider"
    case .flag: return "fr.astrostack.parameter.\(key).toggle"
    case .choice: return "fr.astrostack.parameter.\(key).choice"
    case .points: return "fr.astrostack.curve.\(key).canvas"
    case .text: return "fr.astrostack.parameter.\(key).text"
    }
  }

  @Test("testSchemaRendersEveryKind", arguments: try ProcessRegistry.standard().ids)
  func testSchemaRendersEveryKind(processID: String) throws {
    let type = try #require(try ProcessRegistry.standard().type(id: processID))
    let schema = type.schema
    let defaults = ParamSet(schema: schema)
    let suggested = schema.specs.first {
      guard $0.level == .simple, case .number = $0.kind else { return false }
      return true
    }
    let suggestions =
      suggested.map {
        [Suggestion(paramID: $0.id, value: $0.defaultValue, reason: "from the bundle")]
      } ?? []
    let model = ProcessPanelModel(type: type, params: defaults, suggestions: suggestions)

    let closed = Set(AccessibilityAuditTests.entries(ProcessPanel(model: model)).map(\.id))
    for spec in schema.specs {
      let id = Self.id(processID, spec)
      if spec.level == .simple {
        #expect(closed.contains(id), "\(id) shown")
      } else {
        #expect(!closed.contains(id), "\(id) waits for the disclosure")
      }
    }
    if let suggested {
      #expect(closed.contains("fr.astrostack.parameter.\(processID).\(suggested.id).0.suggestion"))
    }
    #expect(model.params == defaults, "nothing was applied by showing a suggestion")
    #expect(model.card(locale: Locale(identifier: "fr")) != nil, "the process card")

    model.showsAdvanced = true
    let open = Set(AccessibilityAuditTests.entries(ProcessPanel(model: model)).map(\.id))
    #expect(schema.specs.allSatisfy { open.contains(Self.id(processID, $0)) })
  }

  @Test("a suggestion applies its value only when clicked, and an edit reports a change")
  func testSuggestionAndChange() throws {
    let model = ProcessPanelModel(
      type: StretchProcess.self, params: ParamSet(schema: StretchProcess.schema),
      suggestions: [
        Suggestion(paramID: "targetBackground", value: .number(0.12), reason: "darker sky")
      ])
    var changes = 0
    model.onChange = { changes += 1 }
    model.take(model.suggestions[0])
    #expect(model.params["targetBackground"] == .number(0.12) && changes == 1)
    model.set("linked", .flag(false))
    #expect(model.params["linked"] == .flag(false) && changes == 2)
    model.set("unknown", .flag(true))
    #expect(changes == 2, "a refused value changes nothing")
  }
}
