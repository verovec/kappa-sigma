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
      "setfindstar", "spcc", "pcc", "spcc_list",
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

  @Test(
    "a token with a space is quoted whole, flag included; others are unchanged (card 0112)",
    arguments: [
      (
        SirilCommand.stack(
          seq: "r_pp_light_", clause: "rej 3 3", filterIncluded: true,
          out: "/P/M_31 2.astrostack/stacks/run/master_RGB"),
        #"stack r_pp_light_ rej 3 3 -filter-incl "-out=/P/M_31 2.astrostack/stacks/run/master_RGB""#
      ),
      (
        .stack(seq: "r_", clause: "sum", filterIncluded: false, out: "/P/M31/master"),
        "stack r_ sum -out=/P/M31/master"
      ),
      (.load("/P/a b/x"), #"load "/P/a b/x""#), (.save("/P/a b/x"), #"save "/P/a b/x""#),
      (.savepng("/P/a b/x"), #"savepng "/P/a b/x""#),
      (.savetif("/P/a b/x"), #"savetif "/P/a b/x""#), (.load("x"), "load x"),
      (
        .rgbcomp(r: "/a b/r", g: "g", b: "b", lum: "/a b/l", out: "/a b/o"),
        #"rgbcomp "/a b/r" g b "-lum=/a b/l" "-out=/a b/o""#
      ),
      (
        .calibrate(seq: "light", arguments: ["-dark=/L/my darks/d.fits", "-cfa"]),
        #"calibrate light "-dark=/L/my darks/d.fits" -cfa -prefix=pp_"#
      ),
      (
        .calibrateSingle(image: "light_00001", arguments: ["-flat=/L/f f.fits"]),
        #"calibrate_single light_00001 "-flat=/L/f f.fits" -prefix=pp_"#
      ),
      (
        .spcc([#""-oscsensor=Sony IMX571""#, "-catalog=localgaia"]),
        #"spcc "-oscsensor=Sony IMX571" -catalog=localgaia"#
      ),
    ])
  func testSirilCommand_quotesTokensWithSpaces(command: SirilCommand, expected: String) {
    #expect(command.line == expected)
  }

  @Test(
    "the calibrate line keeps -cc=bpm and its map as two words; a map path with a space is quoted",
    arguments: [
      (
        CalibrationMasters(dark: "d.fits", badPixelMap: "d_defects.lst"),
        "calibrate light -dark=d.fits -cc=bpm d_defects.lst -prefix=pp_"
      ),
      (
        CalibrationMasters(dark: "/L/a b/d.fits", badPixelMap: "/L/a b/d_defects.lst"),
        #"calibrate light "-dark=/L/a b/d.fits" -cc=bpm "/L/a b/d_defects.lst" -prefix=pp_"#
      ),
    ])
  func testSirilCommand_calibrateBadPixelMap(masters: CalibrationMasters, expected: String) {
    #expect(SirilCommand.calibrate(seq: "light", arguments: masters.arguments).line == expected)
  }

  @Test(
    "a sequence name with a space is quoted in every sequence verb",
    arguments: [
      (SirilCommand.register(seq: "a b", twoPass: false, transformation: nil), #"register "a b""#),
      (.select(seq: "a b", from: 1, to: 3), #"select "a b" 1 3"#),
      (.unselect(seq: "a b", from: 2, to: 2), #"unselect "a b" 2 2"#),
      (.setref(seq: "a b", index: 4), #"setref "a b" 4"#),
      (.seqapplyreg(seq: "a b", framing: nil), #"seqapplyreg "a b""#),
      (.seqsubsky(seq: "a b", degree: 1, prefix: "bkg_"), #"seqsubsky "a b" 1 -prefix=bkg_"#),
    ])
  func testSirilCommand_quotesSequenceNames(command: SirilCommand, expected: String) {
    #expect(command.line == expected)
  }
}
