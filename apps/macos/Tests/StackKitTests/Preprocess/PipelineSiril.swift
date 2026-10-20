import Foundation
import StackKit
import Synchronization

/// A `SirilRunner` that records every script and plays Siril's file side for the preprocessing
/// path: `register X` writes `X_.seq` (from `sequence`, keyed by the run folder's name) with the
/// calibrated and registered frames, `calibrate_single` its lone frame, `seqapplyreg` the aligned
/// frames, and every `-out=`/`save` target a small FITS carrying a BAYERPAT card.
final class PipelineSiril: Sendable {
  struct Call: Sendable, Equatable {
    var script: String
    var directory: URL
  }

  private let state = Mutex<[Call]>([])
  /// The `.seq` text a registration writes, by folder name (`light_L`); nil: one line per link.
  let sequence: @Sendable (String) -> String?
  /// Runs before each script plays out (a test cancels from here).
  let onRun: @Sendable (String) -> Void

  init(
    sequence: @escaping @Sendable (String) -> String? = { _ in nil },
    onRun: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.sequence = sequence
    self.onRun = onRun
  }

  var calls: [Call] { state.withLock { $0 } }

  var runner: SirilRunner {
    SirilRunner(run: { script, directory, _ in
      let text = script.render()
      self.state.withLock { $0.append(Call(script: text, directory: directory)) }
      self.onRun(text)
      try Task.checkCancellation()
      for line in text.split(separator: "\n").map(String.init) {
        try self.play(line, in: directory)
      }
      return "log: done\n"
    })
  }

  static let healthyLine = "R0 3 3 0.95 0 0.01 30 H 1 0 0 0 1 0 0 0 1"

  private func play(_ line: String, in directory: URL) throws {
    let words = line.split(separator: " ").map(String.init)
    guard let verb = words.first else { return }
    switch verb {
    case "link", "convert": try ingest(words[1], in: directory)
    case "register": try register(words[1], in: directory)
    case "calibrate_single": try Self.frame(directory.appendingPathComponent("pp_" + words[1] + ".fits"))
    case "seqapplyreg": try applyRegistration(words[1], in: directory)
    case "stack", "rgbcomp":
      if let out = words.first(where: { $0.hasPrefix("-out=") }) {
        try Self.frame(Self.target(String(out.dropFirst(5)), in: directory))
      }
    case "save": try Self.frame(Self.target(words[1], in: directory))
    default: break
    }
  }

  private func register(_ target: String, in directory: URL) throws {
    let links = try Self.links(in: directory)
    let text =
      sequence(directory.lastPathComponent)
      ?? links.map { _ in Self.healthyLine }.joined(separator: "\n")
    try Data(text.utf8).write(to: directory.appendingPathComponent(target + "_.seq"))
    let parsed = SirilSequence(parsing: text)
    var registered = 0
    for (index, metric) in parsed.metrics.enumerated() {
      try Self.frame(directory.appendingPathComponent(target + String(format: "_%05d.fits", index + 1)))
      guard metric.fwhm > 0 else { continue }
      registered += 1
      try Self.frame(directory.appendingPathComponent("r_" + target + String(format: "_%05d.fits", registered)))
    }
  }

  private func ingest(_ seq: String, in directory: URL) throws {
    for index in try Self.links(in: directory).indices {
      try Self.frame(directory.appendingPathComponent(seq + String(format: "_%05d.fits", index + 1)))
    }
  }

  private func applyRegistration(_ seq: String, in directory: URL) throws {
    for index in 1...max(1, try Self.links(in: directory).count) {
      try Self.frame(directory.appendingPathComponent("r_" + seq + String(format: "_%05d.fits", index)))
    }
  }

  /// The `00001_…` links of a sequence folder.
  static func links(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.first?.isNumber == true }.sorted()
  }

  static func target(_ name: String, in directory: URL) -> URL {
    let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : directory.appendingPathComponent(name)
    return url.appendingPathExtension("fits")
  }

  /// A frame the size of the golden case's (256×256, 16-bit) with a spurious BAYERPAT, as an
  /// older mono capture's stack inherits.
  static func frame(_ url: URL) throws {
    try TestFITS.write(
      url.lastPathComponent, in: url.deletingLastPathComponent(), width: 256, height: 256,
      cards: ["BAYERPAT": "'RGGB'"])
  }
}
