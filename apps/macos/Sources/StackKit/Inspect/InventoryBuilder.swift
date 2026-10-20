package import Foundation

/// Scans capture folders into an `Inventory` (`inspect.ScanMany`): each folder is walked and its
/// frames classified on their own (header, names, `info.txt`, wheel slots, pixel curves, wheel-order
/// detection); grouping, verdicts and completeness warnings run ONCE over the union, so the
/// calibration in one folder satisfies the lights of another. Deep-sky FITS only: phone/DSLR raws,
/// TIFF stills and videos are not ported.
package struct InventoryBuilder: Sendable {
  /// The site's zone: it decides each frame's observing night.
  package var timeZone: TimeZone
  package var pixels: PixelReader

  static let fitsExtensions: Set<String> = ["fits", "fit", "fts"]
  /// Centre pixels sampled to classify a frame no header or name typed.
  static let statsSample = 200_000

  /// A builder reading FITS files on disk.
  package init(timeZone: TimeZone = .current, pixels: PixelReader = .files) {
    self.timeZone = timeZone
    self.pixels = pixels
  }

  /// Scans `paths` (folders) with the user's overrides. One folder is its own root; several
  /// merge under their common parent.
  package func scan(paths: [String], overrides: InspectOverrides = InspectOverrides()) throws -> Inventory {
    guard !paths.isEmpty else { throw InspectError.noFolders }
    let roots = paths.map(Self.clean)
    var merged = Inventory(root: roots.count == 1 ? roots[0] : Self.commonParent(roots), frames: [])
    for root in roots {
      try Task.checkCancellation()
      let folder = scanFrames(root: root, overrides: overrides)
      merged.frames += folder.frames
      merged.warnings += folder.warnings
      if merged.channelDetection == nil { merged.channelDetection = folder.channelDetection }
    }
    finalize(&merged, overrides: overrides)
    try merged.resolve(overrides.colorModel)
    return merged
  }

  /// One folder: read, then the per-folder fallbacks, in the legacy order.
  private func scanFrames(root: String, overrides: InspectOverrides) -> Inventory {
    var inventory = Inventory(root: root, frames: [])
    for path in InspectWalk.files(under: root, skippingOutput: true) {
      let ext = (path as NSString).pathExtension.lowercased()
      guard Self.fitsExtensions.contains(ext) else { continue }
      do {
        inventory.frames.append(try CaptureFrame(reading: URL(fileURLWithPath: path), timeZone: timeZone))
      } catch {
        inventory.warnings.append("skip \(InspectWalk.relative(path, to: root)): \(error)")
      }
    }
    // info.txt first, so signal detection only runs on what the manifest could not name; physical
    // wheel slots before detection, so a known filter never goes to the guess-prone detector.
    CaptureManifest.apply(under: root, to: &inventory)
    WheelSlots.nameRemaining(&inventory)
    WheelSlots.warnUnnamed(&inventory)
    classifyUnknowns(&inventory)
    if overrides.detectChannels {
      var options = overrides.channel
      if options.order.isEmpty { options = ChannelDetector.Options() }
      inventory.detectChannels(pixels: pixels, options: options)
    }
    return inventory
  }

  /// The steps that must run once over every folder (`finalizeInventory`).
  private func finalize(_ inventory: inout Inventory, overrides: InspectOverrides) {
    inventory.clearSpuriousBayer(pixels: pixels)
    inventory.colorModel = inventory.lightColorModel
    if inventory.colorModel == .mixed {
      inventory.warnings.append(
        "this folder mixes monochrome and one-shot-color lights — one run cannot stack both; "
          + "process them from separate folders")
    }
    inventory.nameColorChannel()
    inventory.regroup()
    if !overrides.excludeSets.isEmpty {
      let removed = inventory.excludeSets(overrides.excludeSets)
      if removed.frames > 0 {
        inventory.warnings.append(
          "\(removed.frames) frame(s) in \(removed.sets) set(s) excluded by user (stray-light artifact)")
      }
    }
    inventory.applyFilterMapping(overrides.filterMap)
    // Last among the grouping steps: verdicts are stored against a set's final id.
    FilterSetClassifier.annotate(&inventory, overrides: overrides.filterSets, pixels: pixels)
    inventory.sessions = SessionInfo.summary(inventory.frames)
    if Night.spansSeveral(inventory.frames) { inventory.warnUndatedSplit() }
    inventory.addCompletenessWarnings()
  }

  /// Folder paths without a trailing slash (`filepath.Clean` for what callers pass).
  static func clean(_ path: String) -> String {
    var out = path
    while out.count > 1 && out.hasSuffix("/") { out.removeLast() }
    return out
  }

  /// The longest shared folder prefix of several roots (display only).
  package static func commonParent(_ roots: [String]) -> String {
    guard var parts = roots.first.map({ clean($0).split(separator: "/", omittingEmptySubsequences: false) }) else {
      return ""
    }
    for root in roots.dropFirst() {
      let other = clean(root).split(separator: "/", omittingEmptySubsequences: false)
      parts = Array(zip(parts, other).prefix { $0 == $1 }.map(\.0))
    }
    if parts.isEmpty { return "" }
    if parts == [""] { return "/" }
    return parts.joined(separator: "/")
  }
}
