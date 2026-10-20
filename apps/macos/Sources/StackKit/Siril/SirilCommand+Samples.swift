extension SirilCommand {
  /// One command per verb the builders emit, plus the script header's verbs.
  ///
  /// What the live grammar test sends to a real Siril in pipe mode. Adding a case to
  /// `SirilCommand` without a sample here fails `testSamplesCoverEveryVerb`.
  package static let samples: [String] =
    [
      "requires 1.2.0", "setext fits", "set32bits",
    ]
    + [
      SirilCommand.link(seq: "light"), .convert(seq: "cal"),
      .calibrate(seq: "light", arguments: ["-dark=d.fits"]),
      .calibrateSingle(image: "light_00001", arguments: ["-dark=d.fits"]),
      .register(seq: "light", twoPass: true, transformation: "homography"),
      .select(seq: "r_light_", from: 1, to: 3), .unselect(seq: "r_light_", from: 2, to: 2),
      .stack(
        seq: "r_light_", clause: "rej winsorized 3 3 -norm=addscale", filterIncluded: true, out: "m"
      ),
      .setref(seq: "light", index: 1), .setfindstarRelaxed,
      .seqapplyreg(seq: "light", framing: "min"),
      .seqsubsky(seq: "light", degree: 1, prefix: "flat_"), .load("missing"), .fmul("1.0"),
      .save("out"),
      .savepng("out"), .savetif("out"), .mirrorx, .subsky(degree: 1), .rmgreen(type: 0),
      .autostretchLinked, .satu(0.12), .platesolve(coords: nil, noFlip: true),
      .rgbcomp(r: "r", g: "g", b: "b", lum: "l", out: "combined"),
    ].map(\.line)
}
