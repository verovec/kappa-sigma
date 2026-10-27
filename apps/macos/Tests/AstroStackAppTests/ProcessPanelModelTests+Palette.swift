import AstroStackApp
import ProcessKit
import Testing

/// The palette menu (card 0139): a template that fills the four visible sources, named when the
/// sources match one, « Custom » otherwise; and the generic greying of a value the stack lacks.
extension ProcessPanelModelTests {
  @Test("testPaletteMenu_replacesSources")
  func testPaletteMenu_replacesSources() throws {
    let type = try #require(ProcessRegistry.standard().type(id: ChannelCombinationProcess.id))
    let panel = ProcessPanelModel(type: type, params: ParamSet(schema: type.schema))
    #expect(panel.paletteOptions.isEmpty, "no bundle yet")
    panel.layerPlanes = ["RGB": 3, "Ha": 1, "OIII": 1]
    #expect(panel.paletteOptions == [.natural, .hoo, .foraxx])
    #expect(panel.palette == .natural)
    panel.choose(palette: .hoo)
    #expect(
      ["rSource", "gSource", "bSource"].map { panel.params.choice($0) } == ["Ha", "OIII", "OIII"])
    #expect(panel.palette == .hoo)
    panel.set("rSource", .choice("OIII"))
    #expect(panel.palette == nil, "no palette matches: Custom")
  }

  @Test("testUnavailableOptions_currentValueNamingAbsentLayer")
  func testUnavailableOptions_currentValueNamingAbsentLayer() throws {
    let type = try #require(ProcessRegistry.standard().type(id: ChannelCombinationProcess.id))
    let panel = ProcessPanelModel(type: type, params: ParamSet(schema: type.schema))
    panel.unavailableOptions["engine"] = ["siril": .app("kept")]  // another greying stays
    panel.layerIDs = ["RGB"]
    panel.set("lSource", .choice("Ha"))
    #expect(panel.unavailableOptions["lSource"]?["Ha"] != nil)
    #expect(
      panel.layerOptions(for: "lSource").contains("Ha"), "listed, greyed, never switched away")
    panel.set("lSource", .choice("none"))
    #expect(panel.unavailableOptions["lSource"] == nil)
    #expect(panel.unavailableOptions["engine"]?["siril"] != nil)
  }
}
