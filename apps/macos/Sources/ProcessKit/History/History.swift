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
  /// The image after the last applied step: a copy, so editing it never changes the history.
  package var current: AstroImage { Self.copy(shown) }

  private var shown: AstroImage
  private let original: AstroImage
  private let header: FITSHeader?
  private var nextNumber: Int
  /// The outputs this history wrote: the only files `save` may remove.
  private var created: Set<String> = []

  /// A history of `original` with its outputs in `directory` (created).
  ///
  /// Every output keeps the descriptive cards of `header` (WCS, object…).
  package init(directory: URL, original: AstroImage, header: FITSHeader? = nil) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    self.original = Self.copy(original)
    self.header = header
    shown = Self.copy(original)
    // Continue after the outputs already in the folder (a reopened project): never overwrite.
    let numbers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .compactMap(Self.stepNumber)
    nextNumber = (numbers.max() ?? 0) + 1
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
    created.insert(file)
    steps.append(Step(processID: processID, params: params, file: file))
    undone.removeAll()
    shown = Self.copy(result)
  }

  /// Goes back one step, reloading the previous output from disk.
  package func undo() throws {
    guard !steps.isEmpty else { throw HistoryError.nothingToUndo }
    // Load first: a failed read leaves the history as it was.
    shown = try image(file: steps.dropLast().last?.file)
    undone.append(steps.removeLast())
  }

  /// Re-applies the last undone step from its output on disk.
  package func redo() throws {
    guard let step = undone.last else { throw HistoryError.nothingToRedo }
    shown = try image(file: step.file)
    steps.append(undone.removeLast())
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

  /// Removes the outputs this history wrote that nothing refers to any more (on project save);
  /// other files in the folder (an earlier session's steps, anything else) are not its to remove.
  package func save() throws {
    let referenced = referencedFiles
    for file in created.subtracting(referenced) {
      try FileManager.default.removeItem(at: directory.appendingPathComponent(file))
      created.remove(file)
    }
  }

  private func image(file: String?) throws -> AstroImage {
    guard let file else { return Self.copy(original) }
    return try FITSFile.read(at: directory.appendingPathComponent(file)).image()
  }

  /// A new image object over the same planes (arrays copy on write).
  private static func copy(_ image: AstroImage) -> AstroImage {
    AstroImage(
      width: image.width, height: image.height, planes: image.planes, metadata: image.metadata)
  }

  /// N for `step-N.fits`.
  private static func stepNumber(_ file: String) -> Int? {
    guard file.hasPrefix("step-"), file.hasSuffix(".fits") else { return nil }
    return Int(file.dropFirst(5).dropLast(5))
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
