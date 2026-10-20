/// The script builders of the legacy engine, one per recorded script shape.
///
/// Ported from `internal/siril/scripts.go`, `postprocess.go` and `mono.go`; each is pinned by
/// `SirilScriptTests` against the scripts the engine actually ran.
package enum SirilScripts {
  /// The inputs of the colour combination (`postprocess.buildCombine`).
  package enum CombineInputs: Equatable, Sendable {
    /// L + R + G + B (`rgbcomp R G B -lum=L`).
    case lrgb(lum: String, r: String, g: String, b: String)
    /// R + G + B.
    case rgb(r: String, g: String, b: String)
    /// A colour master already (OSC): loaded as is.
    case colour(String)
  }

  /// A bias or dark master (`StackMasterScript`).
  package static func stackMaster(seq: String, out: String, frames: Int, options: StackOptions)
    -> SirilScript
  {
    SirilScript([
      .convert(seq: seq),
      .stack(
        seq: seq, clause: StackClause.render(options, frames: frames), filterIncluded: false,
        out: out),
    ])
  }

  /// A single-frame pool promoted as the master (`PromoteLoneFrameScript`): Siril has no
  /// one-image sequences, so the lone frame is converted, re-encoded (`fmul 1.0` under
  /// `set32bits`) and saved, in the same 32-bit [0,1] convention as a stacked master.
  package static func promoteLoneFrame(seq: String, out: String) -> SirilScript {
    SirilScript([.convert(seq: seq), .load("\(seq)_00001"), .fmul("1.0"), .save(out)])
  }

  /// A flat master, calibrated by the bias when there is one (`StackFlatScript`).
  package static func stackFlat(
    seq: String, out: String, bias: String?, frames: Int, options: StackOptions
  ) -> SirilScript {
    var commands: [SirilCommand] = [.convert(seq: seq)]
    var target = seq
    if let bias {
      commands.append(.calibrate(seq: seq, arguments: ["-bias=\(bias)"]))
      target = "pp_" + seq
    }
    commands.append(
      .stack(
        seq: target, clause: StackClause.render(options, frames: frames), filterIncluded: false,
        out: out))
    return SirilScript(commands)
  }

  /// Calibration then registration (`CalibrateRegisterScriptWith`, or the two-pass form).
  package static func calibrateRegister(
    seq: String, masters: CalibrationMasters, ingest: SirilIngest = .link, twoPass: Bool = false
  ) -> SirilScript {
    var script = calibrateOnly(seq: seq, masters: masters, ingest: ingest)
    let target = calibrated(seq, masters: masters)
    script.commands.append(.register(seq: target, twoPass: twoPass, transformation: nil))
    return script
  }

  /// Calibration only, for one night group (`CalibrateOnlyScriptWith`).
  package static func calibrateOnly(
    seq: String, masters: CalibrationMasters, ingest: SirilIngest = .link
  ) -> SirilScript {
    var commands: [SirilCommand] = [ingest.command(seq)]
    if !masters.arguments.isEmpty {
      commands.append(.calibrate(seq: seq, arguments: masters.arguments))
    }
    return SirilScript(commands)
  }

  /// Calibration of a one-frame set (`CalibrateSingleScriptWith`): Siril has no one-image
  /// sequences, so the lone ingested frame is calibrated as an image.
  package static func calibrateSingle(
    seq: String, masters: CalibrationMasters, ingest: SirilIngest = .link
  ) -> SirilScript {
    var commands: [SirilCommand] = [ingest.command(seq)]
    if !masters.arguments.isEmpty {
      commands.append(.calibrateSingle(image: "\(seq)_00001", arguments: masters.arguments))
    }
    return SirilScript(commands)
  }

  /// The calibrated sequence's name (`CalibratedSeq`): `pp_<seq>` when anything calibrates it.
  package static func calibrated(_ seq: String, masters: CalibrationMasters) -> String {
    masters.arguments.isEmpty ? seq : "pp_" + seq
  }

  /// The graded stack of a registered sequence, without the rejected frames (`StackSelectedScript`).
  package static func stackSelected(
    registered: String, count: Int, rejected: [Int], out: String, options: StackOptions
  ) -> SirilScript {
    let seq = registered + "_"
    var commands: [SirilCommand] = []
    if count > 0 { commands.append(.select(seq: seq, from: 1, to: count)) }
    commands += rejected.map { .unselect(seq: seq, from: $0, to: $0) }
    let clause = StackClause.render(options, frames: count - rejected.count)
    commands.append(.stack(seq: seq, clause: clause, filterIncluded: true, out: out))
    return SirilScript(commands)
  }

  /// The parity probe: a no-flip plate solve of one image (`ParityProbeScript`).
  package static func parityProbe(load: String, out: String, coords: String?) -> SirilScript {
    SirilScript([.load(load), .platesolve(coords: coords, noFlip: true), .save(out)])
  }

  /// Two-pass registration of the channel masters onto the smallest common frame.
  package static func alignMasters(seq: String) -> SirilScript {
    SirilScript([
      .link(seq: seq), .register(seq: seq, twoPass: true, transformation: nil),
      .seqapplyreg(seq: seq, framing: "min"),
    ])
  }

  /// One master registered onto a pinned reference, star detection relaxed (`AlignPairScript`).
  package static func alignPair(seq: String) -> SirilScript {
    SirilScript([
      .link(seq: seq), .setfindstarRelaxed, .setref(seq: seq, index: 1),
      .register(seq: seq, twoPass: false, transformation: nil),
    ])
  }

  /// Background flattening then two-pass registration (`FlattenRegister2PassScript`).
  package static func flattenRegister2Pass(seq: String, transformation: String, degree: Int)
    -> SirilScript
  {
    SirilScript([
      .link(seq: seq), .seqsubsky(seq: seq, degree: min(max(degree, 1), 4), prefix: "flat_"),
      .register(seq: "flat_" + seq, twoPass: true, transformation: transformation),
    ])
  }

  /// Two-pass registration (`Register2PassScript`).
  package static func register2Pass(seq: String, transformation: String) -> SirilScript {
    SirilScript([
      .link(seq: seq), .register(seq: seq, twoPass: true, transformation: transformation),
    ])
  }

  /// Applies a registration onto a reference frame (`ApplyRegistrationScript`); a reference of 0
  /// keeps Siril's own.
  package static func applyRegistration(seq: String, reference: Int, framing: String?)
    -> SirilScript
  {
    var commands: [SirilCommand] = []
    if reference > 0 { commands.append(.setref(seq: seq, index: reference)) }
    commands.append(.seqapplyreg(seq: seq, framing: framing?.isEmpty == false ? framing : nil))
    return SirilScript(commands)
  }

  /// Mirrors frames left-right, in place (`MirrorFramesScript`).
  package static func mirrorFrames(_ names: [String]) -> SirilScript {
    SirilScript(names.flatMap { [SirilCommand.load($0), .mirrorx, .save($0)] })
  }

  /// Background removal and green-cast removal (`NeutralizeScript`).
  package static func neutralize(load: String, out: String, backgroundDegree: Int, scnr: Int)
    -> SirilScript
  {
    var commands: [SirilCommand] = [.load(load)]
    if backgroundDegree > 0 { commands.append(.subsky(degree: backgroundDegree)) }
    commands += [.rmgreen(type: scnr), .save(out)]
    return SirilScript(commands)
  }

  /// The Siril finish: linked autostretch, saturation, saves (`FinishScript`).
  package static func finish(
    load: String, out: String, linked: Bool, saturation: Double, formats: [SirilCommand.SaveFormat]
  ) -> SirilScript {
    var commands: [SirilCommand] = [
      .load(load), linked ? .autostretchLinked : .autostretch(linked: false, target: 0.06),
    ]
    if saturation > 0 { commands.append(.satu(saturation)) }
    commands += formats.map { $0.command(out) }
    return SirilScript(commands)
  }

  /// The colour combination into `combined` (`postprocess.buildCombine`).
  package static func combine(_ inputs: CombineInputs, backgroundDegree: Int?) -> SirilScript {
    var commands: [SirilCommand]
    switch inputs {
    case .lrgb(let lum, let r, let g, let b):
      commands = [.rgbcomp(r: r, g: g, b: b, lum: lum, out: "combined"), .load("combined")]
    case .rgb(let r, let g, let b):
      commands = [.rgbcomp(r: r, g: g, b: b, lum: nil, out: "combined"), .load("combined")]
    case .colour(let master):
      commands = [.load(master)]
    }
    if let degree = backgroundDegree { commands.append(.subsky(degree: max(degree, 1))) }
    commands.append(.save("combined"))
    return SirilScript(commands)
  }

  /// The luminance side output's stretch (`mono.go` renderMono).
  package static func monoStretch(
    linear: String, stretched: String, backgroundDegree: Int, target: Double
  ) -> SirilScript {
    SirilScript([
      .load(linear), .subsky(degree: backgroundDegree), .autostretch(linked: false, target: target),
      .save(stretched),
    ])
  }

  /// Loads `load` and saves it as `base` in each format (`ExportScript`, `mono.go` exportMono).
  package static func export(load: String, base: String, formats: [SirilCommand.SaveFormat])
    -> SirilScript
  {
    SirilScript([.load(load)] + formats.map { $0.command(base) })
  }
}
