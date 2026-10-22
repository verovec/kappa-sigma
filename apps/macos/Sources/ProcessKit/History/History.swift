package import Foundation
package import ImageKit

/// The non-destructive history of an image (design §2): every applied step keeps its process,
/// its parameters and its output as a FITS in the project; undo reloads the previous output,
/// snapshots name states that survive undo, and `save` removes outputs nothing refers to.
///
/// A step may also write layers (card 0087: StarNet's starless, a background model) that
/// overlay the bundle for the steps after it (`layers()`). `<folder>.json` beside the folder
/// records the steps so `reopen` finds the history again.
package final class History {
  /// One applied process.
  package struct Step: Equatable, Sendable {
    /// The process's id.
    package let processID: String
    /// The values it ran with.
    package let params: ParamSet
    /// Its output, a file in the history folder.
    package let file: String
    /// The layers it wrote besides its image, by role (files in the history folder).
    package let outputs: [LayerRole: String]
    /// The bundle layers it rewrote, by bundle id (`RGB`, `Ha`…): a geometry step moves them
    /// with its image (card 0090).
    package var bundleLayers: [String: String] = [:]
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
  /// The number the next step's file takes (the manifest records it).
  var nextStepNumber: Int { nextNumber }
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

  /// Puts back a recorded state (`reopen`): the steps' files become this history's own.
  func restore(steps: [Step], undone: [Step], snapshots: [Snapshot], nextNumber: Int) throws {
    let head = try image(file: steps.last?.file)
    self.steps = steps
    self.undone = undone
    self.snapshots = snapshots
    self.nextNumber = max(self.nextNumber, nextNumber)
    shown = head
    created.formUnion(referencedFiles)
  }

  /// Whether there is a step to undo.
  package var canUndo: Bool { !steps.isEmpty }
  /// Whether there is a step to redo.
  package var canRedo: Bool { !undone.isEmpty }

  /// Records `result` as the output of `processID` with `params`, `outputs` as the layers it
  /// wrote and `bundleLayers` as the bundle layers it rewrote; what was undone is dropped.
  ///
  /// Its files keep the head's header, or `header` when the step changed it (a geometry step's
  /// moved plate solution); the steps after it keep that one.
  package func apply(
    processID: String, params: ParamSet, result: AstroImage,
    outputs: [LayerRole: AstroImage] = [:], bundleLayers: [String: AstroImage] = [:],
    header: FITSHeader? = nil
  ) throws {
    let kept = try header ?? headHeader()
    let digits = String(nextNumber)
    let stem = "step-" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    nextNumber += 1
    let file = stem + ".fits"
    try write(result, file, header: kept)
    var written: [LayerRole: String] = [:]
    for (role, image) in outputs {
      let name = stem + "-" + role.rawValue + ".fits"
      try write(image, name, header: kept)
      written[role] = name
    }
    var rewritten: [String: String] = [:]
    for (id, image) in bundleLayers {
      let name = stem + "-" + id + ".fits"
      try write(image, name, header: kept)
      rewritten[id] = name
    }
    var step = Step(processID: processID, params: params, file: file, outputs: written)
    step.bundleLayers = rewritten
    try writeManifest(steps: steps + [step], undone: [], snapshots: snapshots)
    steps.append(step)
    undone.removeAll()
    shown = Self.copy(result)
    if let header { shown.metadata.wcs = WCS(header: header) }
  }

  /// The header the head's file carries (the original's before any step): what the next step
  /// keeps.
  package func headHeader() throws -> FITSHeader? {
    guard let file = steps.last?.file else { return header }
    return try FITSFile.read(at: directory.appendingPathComponent(file)).header
  }

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

  /// The roles the applied steps wrote layers for (no pixel read).
  package var layerRoles: Set<LayerRole> {
    Set(steps.flatMap { $0.outputs.keys })
  }

  /// The layers the applied steps wrote, the latest of each role winning (read from disk): what
  /// overlays the bundle's layers for the next step.
  package func layers() throws -> [LayerRole: AstroImage] {
    var latest: [LayerRole: String] = [:]
    for step in steps { latest.merge(step.outputs) { _, newer in newer } }
    return try latest.mapValues {
      try FITSFile.read(at: directory.appendingPathComponent($0)).image()
    }
  }

  /// Whether `other` started from the same image (size, metadata, pixels): a locked pipeline step
  /// may reuse its output only then (`PipelineReuse`).
  package func hasSameOriginal(as other: History) -> Bool {
    original.width == other.original.width && original.height == other.original.height
      && original.metadata == other.original.metadata && original.planes == other.original.planes
  }

  /// The output of applied step `index` (0 = the first), read back from disk.
  package func output(ofStep index: Int) throws -> AstroImage {
    guard steps.indices.contains(index) else { throw HistoryError.noStep(index) }
    return try image(file: steps[index].file)
  }

  /// Everything one step wrote, read back (a locked pipeline step reuses it all).
  package struct Recorded {
    /// Its image.
    package let result: AstroImage
    /// The layers it wrote, by role.
    package let outputs: [LayerRole: AstroImage]
    /// The bundle layers it rewrote, by id.
    package let bundleLayers: [String: AstroImage]
    /// The header its files carry.
    package let header: FITSHeader
  }

  /// Everything applied step `index` wrote, read back: its image, its layers and its header.
  package func recorded(ofStep index: Int) throws -> Recorded {
    guard steps.indices.contains(index) else { throw HistoryError.noStep(index) }
    let step = steps[index]
    let read = { (file: String) in
      try FITSFile.read(at: self.directory.appendingPathComponent(file)).image()
    }
    let main = try FITSFile.read(at: directory.appendingPathComponent(step.file))
    return Recorded(
      result: try main.image(), outputs: try step.outputs.mapValues(read),
      bundleLayers: try step.bundleLayers.mapValues(read), header: main.header)
  }

  /// Goes back one step, reloading the previous output from disk.
  package func undo() throws {
    guard !steps.isEmpty else { throw HistoryError.nothingToUndo }
    // Load first: a failed read leaves the history as it was.
    let previous = try image(file: steps.dropLast().last?.file)
    let last = steps[steps.count - 1]
    try writeManifest(steps: Array(steps.dropLast()), undone: undone + [last], snapshots: snapshots)
    shown = previous
    undone.append(steps.removeLast())
  }

  /// Re-applies the last undone step from its output on disk.
  package func redo() throws {
    guard let step = undone.last else { throw HistoryError.nothingToRedo }
    let next = try image(file: step.file)
    try writeManifest(steps: steps + [step], undone: Array(undone.dropLast()), snapshots: snapshots)
    shown = next
    steps.append(undone.removeLast())
  }

  /// Names the current state; a name is used once.
  package func snapshot(name: String) throws {
    guard !snapshots.contains(where: { $0.name == name }) else {
      throw HistoryError.duplicateSnapshot(name)
    }
    let snapshot = Snapshot(name: name, file: steps.last?.file)
    try writeManifest(steps: steps, undone: undone, snapshots: snapshots + [snapshot])
    snapshots.append(snapshot)
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
    let kept = steps + undone
    return Set(
      kept.map(\.file) + kept.flatMap { $0.outputs.values }
        + kept.flatMap { $0.bundleLayers.values }
        + snapshots.compactMap(\.file))
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
    try writeManifest()
  }

  private func write(_ image: AstroImage, _ file: String, header: FITSHeader?) throws {
    try FITSFile.create(image, keeping: header, at: directory.appendingPathComponent(file))
    created.insert(file)
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
  /// No applied step has this index.
  case noStep(Int)
  /// No applied step.
  case nothingToUndo
  /// No undone step.
  case nothingToRedo
  /// No snapshot has this name.
  case unknownSnapshot(String)
  /// A snapshot already has this name.
  case duplicateSnapshot(String)
  /// The history's manifest cannot be read back: why.
  case unreadable(String)
}
