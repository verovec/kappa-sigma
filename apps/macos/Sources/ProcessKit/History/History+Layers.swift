internal import Foundation
package import ImageKit

extension History {
  /// The files of the layers the applied steps wrote over the bundle, by layer id.
  ///
  /// The latest bundle layer of each id, then the latest output of each role (by its raw
  /// value): what `StepRunner` caches its uploaded context on.
  package var overlayFiles: [String: String] {
    var files: [String: String] = [:]
    for step in steps { files.merge(step.bundleLayers) { _, newer in newer } }
    for step in steps {
      for (role, file) in step.outputs { files[role.rawValue] = file }
    }
    return files
  }

  /// The bundle layers the applied steps rewrote, the latest of each id winning (read from
  /// disk): they overlay the bundle's layers, under the role outputs, for the next step.
  package func bundleLayers() throws -> [String: AstroImage] {
    var latest: [String: String] = [:]
    for step in steps { latest.merge(step.bundleLayers) { _, newer in newer } }
    return try latest.mapValues {
      try FITSFile.read(at: directory.appendingPathComponent($0)).image()
    }
  }

  /// Everything one step wrote, read back (a locked pipeline step reuses it all).
  package struct Recorded {
    /// Its image.
    package let result: AstroImage
    /// The layers it wrote, by role.
    package let outputs: [LayerRole: AstroImage]
    /// The bundle layers it rewrote, by id.
    package let bundleLayers: [String: AstroImage]
  }

  /// Everything applied step `index` wrote, read back: its image and its layers (each with the
  /// plate solution its file carries).
  package func recorded(ofStep index: Int) throws -> Recorded {
    guard steps.indices.contains(index) else { throw HistoryError.noStep(index) }
    let step = steps[index]
    let read = { (file: String) in
      try FITSFile.read(at: self.directory.appendingPathComponent(file)).image()
    }
    return Recorded(
      result: try read(step.file), outputs: try step.outputs.mapValues(read),
      bundleLayers: try step.bundleLayers.mapValues(read))
  }
}
