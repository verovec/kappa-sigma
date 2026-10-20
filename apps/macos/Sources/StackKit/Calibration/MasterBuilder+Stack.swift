internal import CryptoKit
internal import Foundation

extension MasterBuilder {
  /// Master builds do not stream Siril's lines anywhere yet (0048 wires progress).
  static let quiet: @Sendable (SirilLine) -> Void = { _ in }

  /// Stacks one set (`buildOne`): link its frames as sequence `cal`, run the script, publish the
  /// `.fits`, write the `.sig`, drop the scratch.
  func buildOne(
    _ set: FrameSet, built: [CalibrationMaster], folder: URL, work: URL, publish: Publish,
    into result: inout Result
  ) async throws -> CalibrationMaster {
    guard let type = MasterType(set.key.type) else {
      throw CalibrationError.masterFailed(name: "", reason: "not a calibration set")
    }
    let name = MasterName.make(set.key, recipe: recipeTag(type))
    let final = folder.appendingPathComponent(name).path
    let target: String
    switch publish {
    case .direct: target = final
    case .atomic(let runID): target = folder.appendingPathComponent(".tmp_\(runID)_\(name)").path
    }
    let sequence = work.appendingPathComponent("cal_\(name)")
    let paths = set.frames.map(\.path)
    defer { try? FileManager.default.removeItem(at: sequence) }
    do {
      try Self.link(paths, into: sequence)
      if let note = try await stack(
        set, type: type, name: name, built: built, sequence: sequence, target: target)
      {
        result.warnings.append(note)
      }
      try Self.publish(
        target: target, final: final, signature: PoolSignature.of(paths), frames: paths.count)
    } catch is CancellationError {
      Self.discard(target)
      throw CancellationError()
    } catch {
      Self.discard(target)
      throw CalibrationError.masterFailed(name: name, reason: "\(error)")
    }
    return Self.master(set, type: type, path: final + ".fits")
  }

  /// Runs the right script; returns the pool note, if any (`stackMasterSet`).
  private func stack(
    _ set: FrameSet, type: MasterType, name: String, built: [CalibrationMaster], sequence: URL,
    target: String
  ) async throws -> String? {
    let frames = set.count
    if frames == 1 {
      _ = try await runner.run(
        SirilScripts.promoteLoneFrame(seq: "cal", out: target), sequence, Self.quiet)
      return MasterNotes.lonePromotion(name, type: type)
    }
    let options = recipes.options(type)
    guard type == .flat else {
      _ = try await runner.run(
        SirilScripts.stackMaster(seq: "cal", out: target, frames: frames, options: options),
        sequence, Self.quiet)
      return MasterNotes.thinDarkPool(name, type: type, frames: frames)
    }
    let bias = Self.flatBias(set.key, built)
    do {
      _ = try await runner.run(
        SirilScripts.stackFlat(
          seq: "cal", out: target, bias: bias, frames: frames, options: options), sequence,
        Self.quiet
      )
      return nil
    } catch let error where bias != nil && !(error is CancellationError) {
      // The bias pedestal is a sliver of a flat's level; losing the flat costs the night its
      // vignetting and dust correction. Retry uncalibrated, on fresh links.
      let retry = sequence.deletingLastPathComponent().appendingPathComponent(
        sequence.lastPathComponent + "_uncal")
      defer { try? FileManager.default.removeItem(at: retry) }
      do {
        try Self.link(set.frames.map(\.path), into: retry)
        _ = try await runner.run(
          SirilScripts.stackFlat(
            seq: "cal", out: target, bias: nil, frames: frames, options: options), retry, Self.quiet
        )
      } catch {
        throw error
      }
      return "flat \(name): stacked WITHOUT its bias — flat calibration failed (\(error))"
    }
  }

  /// The dark-flat, else the bias, of the flat's camera (`flatBias`).
  static func flatBias(_ flat: SetKey, _ built: [CalibrationMaster]) -> String? {
    for type in [MasterType.darkFlat, .bias] {
      if let master = built.first(where: { $0.type == type && $0.sameCamera(as: flat) }) {
        return master.path
      }
    }
    return nil
  }

  /// `00001_<name>` symlinks to the frames: Siril's `convert` reads them in this order.
  static func link(_ paths: [String], into folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (index, path) in paths.enumerated() {
      let link = folder.appendingPathComponent(
        String(format: "%05d_", index + 1) + PathMeta.baseName(path))
      try? FileManager.default.removeItem(at: link)
      try FileManager.default.createSymbolicLink(
        atPath: link.path, withDestinationPath: URL(fileURLWithPath: path).standardizedFileURL.path)
    }
  }

  /// Writes the `.sig` first, then moves the master into place: when the `.fits` appears, its
  /// pool record is already there.
  private static func publish(target: String, final: String, signature: String, frames: Int) throws
  {
    let manager = FileManager.default
    let sidecar = PoolSignature.sidecar(of: final + ".fits")
    // The old proof goes first and the new one last: whatever fails in between, no `.sig` ever
    // vouches for frames the master on disk was not stacked from (a rebuild, never a wrong reuse).
    try? manager.removeItem(atPath: sidecar)
    if target != final {
      if manager.fileExists(atPath: final + ".fits") {
        _ = try manager.replaceItemAt(
          URL(fileURLWithPath: final + ".fits"), withItemAt: URL(fileURLWithPath: target + ".fits"))
      } else {
        try manager.moveItem(atPath: target + ".fits", toPath: final + ".fits")
      }
    }
    try Data(PoolSignature.format(hash: signature, frameCount: frames).utf8)
      .write(to: URL(fileURLWithPath: sidecar), options: .atomic)
  }

  /// Removes a partial output.
  private static func discard(_ target: String) {
    try? FileManager.default.removeItem(atPath: target + ".fits")
  }

  /// A short fingerprint of a non-default recipe, so it never overwrites the shared master.
  func recipeTag(_ type: MasterType) -> String {
    let options = recipes.options(type)
    guard options != MasterRecipes().options(type) else { return "" }
    // The clause Siril receives is the recipe's canonical text (rendered for a deep pool, where
    // `auto` rejection resolves to its long-sequence choice).
    let digest = SHA256.hash(data: Data(StackClause.render(options, frames: 100).utf8))
    return digest.prefix(3).map { String(format: "%02x", $0) }.joined()
  }

  /// The master a set produced; its temperature is a representative frame's real one.
  static func master(_ set: FrameSet, type: MasterType, path: String) -> CalibrationMaster {
    var master = CalibrationMaster(type: type, path: path)
    master.filter = set.key.filter
    master.exposureMs = set.key.exposureMs
    master.gain = set.key.gain
    master.offset = set.key.offset
    master.tempMilliC = set.frames.first?.tempMilliC ?? 0
    master.hasTemp = set.frames.first?.hasTemp ?? false
    master.bin = set.key.bin
    master.frameCount = set.count
    master.session = set.key.session
    return master
  }
}
