/// One Siril script command: a typed verb, so the grammar test can enumerate every verb the
/// builders emit (no shell strings).
package enum SirilCommand: Equatable, Sendable {
  /// A file format for the save commands.
  package enum SaveFormat: Equatable, Sendable {
    case fits, png, tif

    func command(_ base: String) -> SirilCommand {
      switch self {
      case .fits: .save(base)
      case .png: .savepng(base)
      case .tif: .savetif(base)
      }
    }
  }

  case link(seq: String)
  case convert(seq: String)
  case calibrate(seq: String, arguments: [String])
  /// One image, for a set Siril cannot make a sequence of.
  case calibrateSingle(image: String, arguments: [String])
  case register(seq: String, twoPass: Bool, transformation: String?)
  case select(seq: String, from: Int, to: Int)
  case unselect(seq: String, from: Int, to: Int)
  case stack(seq: String, clause: String, filterIncluded: Bool, out: String)
  case setref(seq: String, index: Int)
  /// Relaxed star detection, for a pair registration rescue.
  case setfindstarRelaxed
  /// Back to the default star detection (a pipe session outlives the script that relaxed it).
  case setfindstarReset
  case seqapplyreg(seq: String, framing: String?)
  case seqsubsky(seq: String, degree: Int, prefix: String)
  case load(String)
  case save(String)
  /// Multiplies the loaded image by a factor, written as given (`fmul 1.0`).
  case fmul(String)
  case savepng(String)
  case savetif(String)
  case mirrorx
  case subsky(degree: Int)
  /// `subsky -rbf …` (`SubskyRBFCmd`): a radial-basis model for an asymmetric gradient.
  case subskyRBF(smooth: Double, samples: Int, tolerance: Double, dither: Bool)
  case rmgreen(type: Int)
  case autostretchLinked
  case autostretch(linked: Bool, target: Double)
  case satu(Double)
  /// `mtf low mid high`: the histogram transformation of every channel (card 0089's parity).
  case mtf(low: Double, mid: Double, high: Double)
  case platesolve(coords: String?, noFlip: Bool)
  case rgbcomp(r: String, g: String, b: String, lum: String?, out: String)

  /// The command's verb, as Siril reads it.
  package var verb: String {
    switch self {
    case .autostretchLinked: "autostretch"
    case .subskyRBF: "subsky"
    default: String(String(describing: self).prefix { $0.isLetter })
    }
  }

  /// The command line, without the newline.
  package var line: String {
    switch self {
    case .link(let seq): "link \(seq) -out=."
    case .convert(let seq): "convert \(seq) -out=."
    case .calibrate(let seq, let arguments):
      "calibrate \(seq) \(arguments.joined(separator: " ")) -prefix=pp_"
    case .calibrateSingle(let image, let arguments):
      "calibrate_single \(image) \(arguments.joined(separator: " ")) -prefix=pp_"
    case .register(let seq, let twoPass, let transformation):
      "register \(seq)" + (twoPass ? " -2pass" : "")
        + (transformation.map { " -transf=\($0)" } ?? "")
    case .select(let seq, let from, let to): "select \(seq) \(from) \(to)"
    case .unselect(let seq, let from, let to): "unselect \(seq) \(from) \(to)"
    case .stack(let seq, let clause, let filterIncluded, let out):
      "stack \(seq) \(clause)" + (filterIncluded ? " -filter-incl" : "") + " -out=\(out)"
    case .setref(let seq, let index): "setref \(seq) \(index)"
    case .setfindstarRelaxed: "setfindstar -sigma=0.5 -roundness=0.42 -relax=on"
    case .setfindstarReset: "setfindstar reset"
    case .seqapplyreg(let seq, let framing):
      "seqapplyreg \(seq)" + (framing.map { " -framing=\($0)" } ?? "")
    case .seqsubsky(let seq, let degree, let prefix): "seqsubsky \(seq) \(degree) -prefix=\(prefix)"
    default: tail
    }
  }

  /// Lines of the image commands (split for the function-length budget).
  private var tail: String {
    switch self {
    case .load(let name): "load \(name)"
    case .save(let name): "save \(name)"
    case .fmul(let factor): "fmul \(factor)"
    case .savepng(let name): "savepng \(name)"
    case .savetif(let name): "savetif \(name)"
    case .mirrorx: "mirrorx"
    case .subsky(let degree): "subsky \(degree)"
    case .subskyRBF(let smooth, let samples, let tolerance, let dither):
      "subsky -rbf -smooth=\(GoFormat.shortest(smooth)) -samples=\(samples)"
        + " -tolerance=\(GoFormat.shortest(tolerance))" + (dither ? " -dither" : "")
    case .rmgreen(let type): "rmgreen \(type)"
    case .autostretchLinked: "autostretch -linked"
    case .autostretch(let linked, let target):
      // AutostretchCmd: a target outside (0, 0.5] falls back to 0.06.
      "autostretch" + (linked ? " -linked" : "") + " -2.8 "
        + GoFormat.fixed(target > 0 && target <= 0.5 ? target : 0.06, decimals: 3)
    case .satu(let amount): "satu \(GoFormat.fixed(amount, decimals: 2))"
    case .mtf(let low, let mid, let high):
      "mtf \(GoFormat.shortest(low)) \(GoFormat.shortest(mid)) \(GoFormat.shortest(high))"
    case .platesolve(let coords, let noFlip):
      "platesolve" + (coords.map { " \($0)" } ?? "") + (noFlip ? " -noflip" : "")
    case .rgbcomp(let r, let g, let b, let lum, let out):
      "rgbcomp \(r) \(g) \(b)" + (lum.map { " -lum=\($0)" } ?? "") + " -out=\(out)"
    default: ""
    }
  }
}
