import StackKit
import Testing

/// A night marked dual-band while its folder was imported alone must stay marked once the
/// project scans every folder together: a single-night scan keys its sets without the night
/// (`s:`), a multi-night scan with it (`s:2026-09-22`). The PO's M 31 lost its Hα this way: the
/// override matched no set, the 36 dual-band frames stacked into the broadband lane.
@Suite("FilterSetClassifier.annotate — an override follows its night across scans")
struct FilterSetOverrideNightTests {
  static func light(_ path: String, night: String, gain: Int) -> CaptureFrame {
    var frame = FilterSetScanTests.osc(path, .light, exposureMs: 300_000)
    frame.session = night
    frame.gain = gain
    return frame
  }

  static let broadband = light("bb.fits", night: "2026-09-14", gain: 0)
  static let dualband = light("db.fits", night: "2026-09-22", gain: 100)

  static func dualbandSet(_ inventory: Inventory) throws -> FrameSet {
    try #require(inventory.sets.first { $0.frames.map(\.path) == ["db.fits"] })
  }

  @Test("a set scanned alone stores its override under the night, which the joint scan matches")
  func testOverrideID_singleNightScanCarriesTheNight() throws {
    let alone = FilterSetScanTests.inventory([Self.dualband])
    let set = try Self.dualbandSet(alone)
    #expect(set.key.session.isEmpty)
    #expect(set.overrideID.hasSuffix("|s:2026-09-22"))

    var joint = FilterSetScanTests.inventory([Self.broadband, Self.dualband])
    FilterSetClassifier.annotate(
      &joint, overrides: [set.overrideID: .dualband], pixels: FilterSetScanTests.reader([:]))
    #expect(try Self.dualbandSet(joint).filterSet == .dualband)
    #expect(joint.warnings.isEmpty)
  }

  @Test("the night-qualified override still applies when the folder is scanned alone again")
  func testAnnotate_nightQualifiedOverrideOnSingleNightScan() throws {
    let qualified = try Self.dualbandSet(FilterSetScanTests.inventory([Self.dualband])).overrideID
    var alone = FilterSetScanTests.inventory([Self.dualband])
    FilterSetClassifier.annotate(
      &alone, overrides: [qualified: .dualband], pixels: FilterSetScanTests.reader([:]))
    #expect(try Self.dualbandSet(alone).filterSet == .dualband)
  }

  @Test("an override recorded without its night finds the one dated set it can only mean")
  func testAnnotate_undatedOverrideResolvesToItsOnlyNight() throws {
    let undated = try Self.dualbandSet(FilterSetScanTests.inventory([Self.dualband])).key.id
    #expect(undated.hasSuffix("|s:"))
    var joint = FilterSetScanTests.inventory([Self.broadband, Self.dualband])
    FilterSetClassifier.annotate(
      &joint, overrides: [undated: .dualband], pixels: FilterSetScanTests.reader([:]))
    #expect(try Self.dualbandSet(joint).filterSet == .dualband)
    #expect(joint.sets.filter { $0.filterSet == .dualband }.count == 1)
  }

  @Test("an undated override two nights could mean applies to neither and says so")
  func testAnnotate_ambiguousUndatedOverrideWarns() throws {
    let first = Self.light("a.fits", night: "2026-09-21", gain: 100)
    let undated = try #require(
      FilterSetScanTests.inventory([first]).sets.first { $0.key.type == .light }?.key.id)
    var joint = FilterSetScanTests.inventory([first, Self.dualband])
    FilterSetClassifier.annotate(
      &joint, overrides: [undated: .dualband], pixels: FilterSetScanTests.reader([:]))
    #expect(joint.sets.allSatisfy { $0.filterSet == .unknown })
    #expect(joint.warnings.count == 1)
    #expect(joint.warnings.first?.contains("2 nights") == true)
  }

  @Test("an override that matches no light set is a warning, never silence")
  func testAnnotate_unmatchedOverrideWarns() {
    var inventory = FilterSetScanTests.inventory([Self.broadband])
    let stale = "LIGHT|M 31|RGB|e300000|g100o50b1|i0|t-17|s:2026-09-22"
    FilterSetClassifier.annotate(
      &inventory, overrides: [stale: .dualband], pixels: FilterSetScanTests.reader([:]))
    #expect(inventory.sets.allSatisfy { $0.filterSet == .unknown })
    #expect(inventory.warnings.count == 1)
    #expect(inventory.warnings.first?.contains(stale) == true)
  }
}
