import ProcessKit
import Testing

/// Card 0194: a kept profile's combination is fitted to the layers the stack holds before it
/// becomes step 0 — slot by slot, the replaced ones named (R2).
@Suite("ChannelCombination reconcile: a profile's sources the stack lacks fall back, and say so")
struct ChannelCombinationReconcileTests {
  /// One row: the profile's R, G, B, L sources, the bundle, the sources kept and the slots dropped.
  struct Case: Sendable, CustomTestStringConvertible {
    let profile: [String]
    let planes: [String: Int]
    let sources: [String]
    let dropped: [String]
    var testDescription: String {
      "\(profile.joined(separator: ",")) on \(planes.keys.sorted().joined(separator: "/"))"
    }
  }

  static func mono(_ ids: String...) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: ids.map { ($0, 1) })
  }

  /// `sources` with weights, blacks and L opacity off their defaults: a profile's own values.
  static func params(_ sources: [String]) throws -> ParamSet {
    var params = ParamSet(schema: ChannelCombinationProcess.schema)
    try ChannelCombinationProcess.set(sources: sources, on: &params)
    try params.set("rWeight", .number(1.5))
    try params.set("bBlack", .number(0.002))
    try params.set("lOpacity", .number(0.8))
    return params
  }

  @Test(
    "testReconciled_DropsAbsentSlots",
    arguments: [
      // The PO's Orion stack (card 0170): a kept LRGB profile on L + Hα.
      Case(
        profile: ["R", "G", "B", "L"], planes: mono("L", "Ha"), sources: ["L", "L", "L", "L"],
        dropped: ["rSource", "gSource", "bSource"]),
      Case(
        profile: ["SII", "Ha", "OIII", "none"], planes: mono("Ha", "OIII"),
        sources: ["Ha", "Ha", "OIII", "none"], dropped: ["rSource"]),
      Case(
        profile: ["R", "G", "B", "L"], planes: mono("R", "G", "B"),
        sources: ["R", "G", "B", "none"], dropped: ["lSource"]),
      // An OSC profile's empty values load as `RGB.r/.g/.b`: on a mono stack, what it opens on.
      Case(
        profile: ["RGB.r", "RGB.g", "RGB.b", "none"], planes: mono("L", "R", "G", "B", "Ha"),
        sources: ["R", "G", "B", "none"], dropped: ["rSource", "gSource", "bSource"]),
      Case(
        profile: ["Ha", "Ha*OIII", "OIII", "none"], planes: mono("L", "Ha"),
        sources: ["Ha", "L", "L", "none"], dropped: ["gSource", "bSource"]),
      Case(
        profile: ["R", "G", "B", "L"], planes: ["RGB": 3, "Ha": 1],
        sources: ["RGB.r", "RGB.g", "RGB.b", "none"],
        dropped: ["rSource", "gSource", "bSource", "lSource"]),
    ])
  func testReconciled_DropsAbsentSlots(row: Case) throws {
    let profile = try Self.params(row.profile)
    let result = try ChannelCombinationProcess.reconciled(profile: profile, planes: row.planes)
    #expect(ChannelCombinationProcess.slotSources.map(result.params.choice) == row.sources)
    #expect(result.dropped == row.dropped)
    let layerIDs = Set(row.planes.keys)
    #expect(ChannelCombinationProcess.unavailableReasons(result.params, layerIDs: layerIDs).isEmpty)
    // Only sources move: the profile's weights, black points and L opacity are kept.
    var expected = profile
    try ChannelCombinationProcess.set(sources: row.sources, on: &expected)
    #expect(result.params == expected)
  }

  @Test(
    "testReconciled_Identity: a profile whose every source exists is returned as it is",
    arguments: [
      Case(
        profile: ["RGB.r", "RGB.g", "RGB.b", "none"], planes: ["RGB": 3],
        sources: ["RGB.r", "RGB.g", "RGB.b", "none"], dropped: []),
      Case(
        profile: ["R", "G", "B", "L"], planes: mono("L", "R", "G", "B", "Ha"),
        sources: ["R", "G", "B", "L"], dropped: []),
      // A custom combination of present layers is the profile's choice: never « corrected ».
      Case(
        profile: ["Ha", "G", "B", "L"], planes: mono("L", "R", "G", "B", "Ha"),
        sources: ["Ha", "G", "B", "L"], dropped: []),
      Case(
        profile: ["L", "L", "L", "none"], planes: mono("L", "R", "G", "B"),
        sources: ["L", "L", "L", "none"], dropped: []),
    ])
  func testReconciled_Identity(row: Case) throws {
    let profile = try Self.params(row.profile)
    let result = try ChannelCombinationProcess.reconciled(profile: profile, planes: row.planes)
    #expect(result.params == profile)
    #expect(result.dropped.isEmpty)
    #expect(
      ChannelCombinationProcess.profileNotes(
        profile: profile, params: result.params, layerIDs: Set(row.planes.keys)
      ).isEmpty)
  }

  @Test("the replaced slots carry a note naming the layer the profile asked for")
  func testProfileNotes() throws {
    let planes = Self.mono("L", "Ha")
    let profile = try Self.params(["R", "Ha*OIII", "B", "L"])
    let params = try ChannelCombinationProcess.reconciled(profile: profile, planes: planes).params
    let reason = ChannelCombinationProcess.profileReason
    #expect(ChannelCombinationProcess.rowReasons.contains(reason))
    #expect(
      ChannelCombinationProcess.profileNotes(
        profile: profile, params: params, layerIDs: Set(planes.keys)) == [
          "rSource": RowNote(reason: reason, subject: "R"),
          "gSource": RowNote(reason: reason, subject: EmissionLine.name(ofLayer: "OIII")),
          "bSource": RowNote(reason: reason, subject: "B"),
        ])
    // A slot set back to what the profile asked is no longer « replaced »: its own note
    // (`unavailableReasons`) says why it cannot run.
    var back = params
    try back.set("rSource", .choice("R"))
    let notes = ChannelCombinationProcess.profileNotes(
      profile: profile, params: back, layerIDs: Set(planes.keys))
    #expect(Set(notes.keys) == ["gSource", "bSource"])
  }

  @Test(
    "testReconciled_PlaneTokenOnMonoLayer: a colour plane of a one-plane layer is a lost source",
    arguments: [
      // A profile copied from an OSC dual-band stack (Hα was a colour lane), kept on a mono one.
      Case(
        profile: ["Ha.r", "Ha.g", "Ha.b", "none"], planes: mono("Ha", "OIII"),
        sources: ["Ha", "OIII", "OIII", "none"], dropped: ["rSource", "gSource", "bSource"]),
      Case(
        profile: ["Ha.r", "OIII", "OIII", "L.g"], planes: mono("L", "Ha", "OIII"),
        sources: ["Ha", "OIII", "OIII", "none"], dropped: ["rSource", "lSource"]),
      // The same tokens on a colour lane are read: the profile as it is.
      Case(
        profile: ["Ha.r", "Ha.g", "Ha.b", "none"], planes: ["Ha": 3, "OIII": 1],
        sources: ["Ha.r", "Ha.g", "Ha.b", "none"], dropped: []),
    ])
  func testReconciled_PlaneTokenOnMonoLayer(row: Case) throws {
    let profile = try Self.params(row.profile)
    let result = try ChannelCombinationProcess.reconciled(profile: profile, planes: row.planes)
    #expect(ChannelCombinationProcess.slotSources.map(result.params.choice) == row.sources)
    #expect(result.dropped == row.dropped)
    let layerIDs = Set(row.planes.keys)
    #expect(
      ChannelCombinationProcess.unavailableReasons(
        result.params, layerIDs: layerIDs, planes: row.planes
      ).isEmpty)
    let notes = ChannelCombinationProcess.profileNotes(
      profile: profile, params: result.params, layerIDs: layerIDs, planes: row.planes)
    #expect(Set(notes.keys) == Set(row.dropped))
    // The layer is there: the note says the profile asked for a plane of it, not a lost layer.
    #expect(
      notes.values.allSatisfy { $0.reason == ChannelCombinationProcess.profilePlaneReason })
    #expect(
      ChannelCombinationProcess.rowReasons.contains(ChannelCombinationProcess.profilePlaneReason))
  }

  @Test("the row of a slot reading a colour plane of a one-plane layer says so, and greys it")
  func testUnavailableReasons_PlaneTokenOnMonoLayer() throws {
    let params = try Self.params(["Ha.r", "OIII", "S.g", "none"])
    let planes = Self.mono("Ha", "OIII")
    let layerIDs = Set(planes.keys)
    let reason = ChannelCombinationProcess.planeReason
    #expect(ChannelCombinationProcess.rowReasons.contains(reason))
    #expect(
      ChannelCombinationProcess.unavailableReasons(params, layerIDs: layerIDs, planes: planes) == [
        "rSource": RowNote(reason: reason, subject: EmissionLine.name(ofLayer: "Ha")),
        // An absent layer stays « lacking », whatever its token.
        "bSource": RowNote(reason: ChannelCombinationProcess.missingLayerReason, subject: "S"),
      ])
    #expect(
      ChannelCombinationProcess.unavailableOptions(params, layerIDs: layerIDs, planes: planes) == [
        "rSource": ["Ha.r": reason],
        "bSource": ["S.g": ChannelCombinationProcess.missingLayerReason],
      ])
    // Without the plane counts only presence is judged: what every caller got before.
    #expect(
      Set(ChannelCombinationProcess.unavailableReasons(params, layerIDs: layerIDs).keys)
        == ["bSource"])
  }
}
