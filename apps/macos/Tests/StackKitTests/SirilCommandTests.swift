import StackKit
import Testing

@Suite("SirilCommand: one typed case per verb")
struct SirilCommandTests {
  @Test("the live samples cover every verb a command can have")
  func testSamplesCoverEveryVerb() {
    let sampledVerbs = Set(SirilCommand.samples.map { String($0.split(separator: " ")[0]) })
    let verbs: Set<String> = [
      "link", "convert", "calibrate", "register", "select", "unselect", "stack", "setref",
      "seqapplyreg", "seqsubsky", "load", "save", "savepng", "savetif", "mirrorx", "subsky",
      "rmgreen", "autostretch", "satu", "platesolve", "rgbcomp", "fmul", "calibrate_single",
      "setfindstar",
    ]
    #expect(verbs.isSubset(of: sampledVerbs))
    #expect(sampledVerbs.subtracting(verbs) == ["requires", "setext", "set32bits"])
  }

  @Test(
    "each command's verb is the first word of its line",
    arguments: [
      SirilCommand.autostretchLinked, .autostretch(linked: false, target: 0.06),
      .seqapplyreg(seq: "s", framing: nil), .rgbcomp(r: "r", g: "g", b: "b", lum: nil, out: "o"),
      .platesolve(coords: "10.68,41.27", noFlip: false), .satu(0.125),
      .mtf(low: 0.002, mid: 0.02, high: 0.95),
    ])
  func testSirilCommand_verbMatchesLine(_ command: SirilCommand) {
    #expect(command.line.split(separator: " ").first.map(String.init) == command.verb)
  }

  @Test(
    "number formats match the legacy verbs (%.2f, %.3f, autostretch fallback)",
    arguments: [
      (SirilCommand.satu(0.125), "satu 0.12"), (.satu(0.12), "satu 0.12"),
      (.autostretch(linked: false, target: 0.25), "autostretch -2.8 0.250"),
      (.autostretch(linked: true, target: 0.9), "autostretch -linked -2.8 0.060"),
      (.autostretch(linked: false, target: 0), "autostretch -2.8 0.060"),
      (.mtf(low: 0.002, mid: 0.02, high: 0.95), "mtf 0.002 0.02 0.95"),
    ])
  func testSirilCommand_numbers(command: SirilCommand, expected: String) {
    #expect(command.line == expected)
  }
}
