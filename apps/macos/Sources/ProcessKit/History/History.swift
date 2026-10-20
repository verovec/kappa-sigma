package import Foundation
package import ImageKit

/// The non-destructive history of an image (design §2): every applied step keeps its process,
/// its parameters and its output as a FITS in the project; undo reloads the previous output,
/// snapshots name states that survive undo, and `save` removes outputs nothing refers to.
package final class History {
  /// One applied process.
  package struct Step: Equatable, Sendable {
    /// The process's id.
    package let processID: String
    /// The values it ran with.
    package let params: ParamSet
    /// Its output, a file in the history folder.
    package let file: String
  }

  /// A named state ("v9"): the output of a step, or the original (`file == nil`).
  package struct Snapshot: Equatable, Sendable {
    /// The name shown in the sidebar.
    package let name: String
    /// The output it names; `nil` for the original image.
    package let file: String?
  }

  /// The folder holding the step outputs (inside the project package).
  package let directory: URL
  /// The applied steps, oldest first.
  package private(set) var steps: [Step] = []
  /// Undone steps, the next redo last.
  package private(set) var undone: [Step] = []
  /// Named states, in creation order.
  package private(set) var snapshots: [Snapshot] = []
  /// The image after the last applied step.
  package private(set) var current: AstroImage

  private let original: AstroImage
  private let header: FITSHeader?
  private var nextNumber = 1

  /// A history of `original` writing its outputs into `directory` (created), with `header`'s
  /// descriptive cards (WCS, object…) in every output.
  package init(directory: URL, original: AstroImage, header: FITSHeader? = nil) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    self.original = original
    self.header = header
    current = original
  }

  /// Whether there is a step to undo.
  package var canUndo: Bool { !steps.isEmpty }
  /// Whether there is a step to redo.
  package var canRedo: Bool { !undone.isEmpty }

  /// Records `result` as the output of `processID` with `params`; what was undone is dropped.
  package func apply(processID: String, params: ParamSet, result: AstroImage) throws {
    let digits = String(nextNumber)
    let file = "step-" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits + ".fits"
    nextNumber += 1
    try FITSFile.create(result, keeping: header, at: directory.appendingPathComponent(file))
    steps.append(Step(processID: processID, params: params, file: file))
    undone.removeAll()
    current = result
  }

  /// Goes back one step, reloading the previous output from disk.
  package func undo() throws {
    guard let step = steps.popLast() else { throw HistoryError.nothingToUndo }
    undone.append(step)
    current = try image(file: steps.last?.file)
  }

  /// Re-applies the last undone step from its output on disk.
  package func redo() throws {
    guard let step = undone.popLast() else { throw HistoryError.nothingToRedo }
    steps.append(step)
    current = try image(file: step.file)
  }

  /// Names the current state; a name is used once.
  package func snapshot(name: String) throws {
    guard !snapshots.contains(where: { $0.name == name }) else {
      throw HistoryError.duplicateSnapshot(name)
    }
    snapshots.append(Snapshot(name: name, file: steps.last?.file))
  }

  /// The image a snapshot names (the viewer's compare reference, 0042).
  package func image(snapshot name: String) throws -> AstroImage {
    guard let snapshot = snapshots.first(where: { $0.name == name }) else {
      throw HistoryError.unknownSnapshot(name)
    }
    return try image(file: snapshot.file)
  }

  /// The outputs still reachable: applied, undone (redo) and snapshotted.
  package var referencedFiles: Set<String> {
    Set(steps.map(\.file) + undone.map(\.file) + snapshots.compactMap(\.file))
  }

  /// Bytes of the reachable outputs, counted against the project's disk budget (0068).
  package var diskBytes: Int {
    referencedFiles.reduce(0) { total, file in
      let path = directory.appendingPathComponent(file).path
      return total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0)
    }
  }

  /// Removes the outputs nothing refers to any more (on project save).
  package func save() throws {
    let manager = FileManager.default
    for file in try manager.contentsOfDirectory(atPath: directory.path)
    where file.hasSuffix(".fits") && !referencedFiles.contains(file) {
      try manager.removeItem(at: directory.appendingPathComponent(file))
    }
  }

  private func image(file: String?) throws -> AstroImage {
    guard let file else { return original }
    return try FITSFile.read(at: directory.appendingPathComponent(file)).image()
  }
}

/// A history operation that cannot be done.
package enum HistoryError: Error, Equatable, Sendable {
  /// No applied step.
  case nothingToUndo
  /// No undone step.
  case nothingToRedo
  /// No snapshot has this name.
  case unknownSnapshot(String)
  /// A snapshot already has this name.
  case duplicateSnapshot(String)
}
