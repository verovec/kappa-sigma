import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0129 on the installed Siril: its own lists, merged with the committed OpenNGC overlay.
@Suite(
  "Live sky catalogue — the installed Siril's lists", .liveFixtures, .tags(.live),
  .enabled(
    if: FileManager.default.isExecutableFile(atPath: SirilTool.path()), "siril-cli absent"),
  .timeLimit(.minutes(1)))
struct SkyCatalogueLiveTests {
  @Test("Sh2-132 at 334.6986°, +56.1348°; M 31 typed and named; every list read")
  func testSh2132FromInstalledSiril() throws {
    let catalogue = try SkyCatalogue.installed()
    let sh2 = try #require(catalogue.object(named: "Sh 2-132"))
    #expect(abs(sh2.raDeg - 334.6986) <= 1e-4 && abs(sh2.decDeg - 56.1348) <= 1e-4)
    let m31 = try #require(catalogue.object(named: "NGC 224"))
    #expect(m31.name == "M31" && m31.type == "G" && m31.commonNames.contains("Andromeda Galaxy"))
    #expect(Set(catalogue.objects.map(\.source)) == Set(SkyObject.Source.allCases))
    #expect(catalogue.search("andromeda", limit: 3).first?.name == "M31")
  }
}
