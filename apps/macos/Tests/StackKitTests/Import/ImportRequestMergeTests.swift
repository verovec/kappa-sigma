import StackKit
import Testing

/// Two imports of one project make one run: the later one adds its folders and choices without
/// dropping the earlier overrides.
@Suite("ImportRequest.merging — every import's choices reach the run")
struct ImportRequestMergeTests {
  static let dualbandNight = "LIGHT|M 31|RGB|e300000|g100o50b1|i0|t-17|s:2026-09-22"

  @Test("a later import without overrides keeps the earlier dual-band night and exclusions")
  func testLaterImportKeepsEarlierOverrides() {
    var first = ImportRequest(paths: ["/c/M31-DB"])
    first.filterSets = [Self.dualbandNight: .dualband]
    first.calibExclude = ["dark|RGB|g100o50b1|e300000|t-17"]
    first.colorModel = .osc
    first.forceCalibration = true
    let second = ImportRequest(paths: ["/c/M31-BB"])

    let merged = first.merging(second)
    #expect(merged.paths == ["/c/M31-DB", "/c/M31-BB"])
    #expect(merged.filterSets == [Self.dualbandNight: .dualband])
    #expect(merged.calibExclude == first.calibExclude)
    #expect(merged.colorModel == .osc, "auto defers to the earlier choice")
    #expect(!merged.forceCalibration, "the later import did not force")
    #expect(second.merging(first).forceCalibration == first.forceCalibration)
  }

  @Test("on a conflict the later choice wins; lists are unions without repeats")
  func testLaterChoiceWins() {
    var first = ImportRequest(paths: ["/c/A", "/c/B"])
    first.filterSets = [Self.dualbandNight: .dualband]
    first.filterMap = ["Ha": "ignore"]
    first.excludeSets = ["s1"]
    var second = ImportRequest(paths: ["/c/B", "/c/C"])
    second.filterSets = [Self.dualbandNight: .broadband]
    second.filterMap = ["Ha": "Ha", "L": "L"]
    second.excludeSets = ["s1", "s2"]
    second.colorModel = .mono
    second.forceCalibration = true

    let merged = first.merging(second)
    #expect(merged.paths == ["/c/A", "/c/B", "/c/C"])
    #expect(merged.filterSets == [Self.dualbandNight: .broadband])
    #expect(merged.filterMap == ["Ha": "Ha", "L": "L"])
    #expect(merged.excludeSets == ["s1", "s2"])
    #expect(merged.colorModel == .mono && merged.forceCalibration)
  }
}
