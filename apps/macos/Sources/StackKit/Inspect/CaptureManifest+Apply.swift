internal import Foundation

extension CaptureManifest {
  /// Finds every `info.txt` (or `info.txt.txt`) under `root` and fills the frames of its capture
  /// sub-folders (`applyManifests`).
  ///
  /// Best-effort: every problem becomes a warning.
  package static func apply(under root: String, to inventory: inout Inventory) {
    let manifests = InspectWalk.files(under: root, skippingOutput: false).filter { path in
      PathMeta.baseName(path).wholeMatch(of: /(?i)info\.txt(\.txt)?/) != nil
    }
    guard !manifests.isEmpty else { return }
    var byFolder: [String: [Int]] = [:]
    for (index, frame) in inventory.frames.enumerated() {
      byFolder[InspectWalk.parent(frame.path), default: []].append(index)
    }
    for path in manifests {
      apply(manifestAt: path, byFolder: byFolder, to: &inventory)
    }
  }

  /// One manifest: physical wheel slots, when the frames carry them, make it a slot→name legend;
  /// otherwise its slots map positionally onto the chronological capture sub-folders.
  private static func apply(
    manifestAt path: String, byFolder: [String: [Int]], to inventory: inout Inventory
  ) {
    let label = InspectWalk.relative(path, to: inventory.root)
    guard let data = FileManager.default.contents(atPath: path),
      let text = String(bytes: data, encoding: .utf8)
    else {
      inventory.warnings.append("\(label): read failed")
      return
    }
    let manifest = CaptureManifest(parsing: text)
    inventory.warnings += manifest.warnings.map { "\(label): \($0)" }
    let folders = captureFolders(in: InspectWalk.parent(path), byFolder: byFolder)
    if WheelSlots.assign(manifest, folders: folders, byFolder: byFolder, to: &inventory) { return }
    guard !manifest.slots.isEmpty else { return }
    let aligned = min(manifest.slots.count, folders.count)
    for (slot, folder) in zip(manifest.slots, folders) {
      for index in byFolder[folder] ?? [] {
        manifest.fill(&inventory.frames[index], from: slot)
      }
    }
    if manifest.slots.count != folders.count {
      inventory.warnings.append(
        "\(label): \(manifest.slots.count) filter slots but \(folders.count) capture folders — "
          + "mapped the first \(aligned) in capture order, rest left to detection")
    }
  }

  /// Folders at or below `folder` that hold frames, by the capture timestamp in their name.
  static func captureFolders(in folder: String, byFolder: [String: [Int]]) -> [String] {
    let prefix = folder + "/"
    func key(_ path: String) -> String {
      let base = PathMeta.baseName(path)
      let stamp = base.firstMatch(of: /\d{4}-\d{2}-\d{2}[_-]\d{2}[_-]\d{2}[_-]\d{2}/)
      return stamp.map { String($0.output) } ?? base
    }
    return byFolder.keys.filter { $0 == folder || $0.hasPrefix(prefix) }.sorted { lhs, rhs in
      let (left, right) = (key(lhs), key(rhs))
      return left != right ? left < right : lhs < rhs
    }
  }

  /// Fills one frame of a sub-run from its slot, only where header and names left a blank; a
  /// manifest filter implies a light.
  func fill(_ frame: inout CaptureFrame, from slot: Slot) {
    guard !frame.type.isCalibration else { return }
    if frame.filter.isEmpty, !slot.filter.isEmpty {
      frame.filter = slot.filter
      frame.classSource = .manifest
      frame.filterConfidence = 1
      if frame.type == .unknown { frame.type = .light }
    }
    if frame.gain == 0, slot.hasGain {
      frame.gain = slot.gain
      frame.hasGain = true
    }
    if frame.exposureMs == 0, slot.exposureMs > 0 { frame.exposureMs = slot.exposureMs }
    fillTemperature(&frame)
  }

  /// The manifest's temperature, where the frame has none.
  func fillTemperature(_ frame: inout CaptureFrame) {
    guard !frame.hasTemp, hasTemp else { return }
    frame.tempMilliC = tempMilliC
    frame.hasTemp = true
  }
}
