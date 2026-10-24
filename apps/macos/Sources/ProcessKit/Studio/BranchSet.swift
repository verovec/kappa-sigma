package import Foundation
package import ImageKit

/// The branches of one stack (card 0118): a `Branch` per bundle layer, its history in
/// `<folder>/<layerID>/`, opened when its manifest exists or at its first step — a stack never
/// branched writes nothing.
package final class BranchSet {
  /// Where the branch histories are: `branches` beside the main `history` folder.
  package let folder: URL
  private let header: FITSHeader?
  private let schema: (String) -> ParamSchema?
  private var opened: [String: Branch] = [:]

  /// The branches recorded in `folder` over the layers of `bundle`.
  ///
  /// Each step keeps `header`'s descriptive cards; `schema` reads a process's stored values back.
  package init(
    folder: URL, bundle: PipelineBundle, header: FITSHeader? = nil,
    schema: @escaping (String) -> ParamSchema?
  ) throws {
    self.folder = folder
    self.header = header
    self.schema = schema
    for (id, layer) in bundle.layers {
      let directory = folder.appendingPathComponent(id)
      guard try HistoryManifest.read(in: directory) != nil else { continue }
      opened[id] = try open(id, layer: layer)
    }
  }

  /// The folder of the branches of the main history in `directory`: `branches` beside it.
  package static func folder(besides directory: URL) -> URL {
    directory.deletingLastPathComponent().appendingPathComponent("branches")
  }

  /// The branch of `layerID`, if it was ever opened.
  package func branch(_ layerID: String) -> Branch? { opened[layerID] }

  /// The branch of `layerID`, opened over `layer` when it is not yet.
  func branch(_ layerID: String, layer: AstroImage) throws -> Branch {
    if let branch = opened[layerID] { return branch }
    let branch = try open(layerID, layer: layer)
    opened[layerID] = branch
    return branch
  }

  /// The branches opened so far (a manifest on disk, or a step this session).
  package var all: [Branch] { Array(opened.values) }

  /// The file of each branch head, by layer id (branches without an applied step left out).
  package var heads: [String: String] {
    opened.compactMapValues(\.headFile)
  }

  /// `bundle` with each branch head over its layer, measured, the stack's continuum fit kept (a
  /// branch moves no pixel); the head over `baseID` gives the image's statistics too.
  package func overlay(_ bundle: PipelineBundle, baseID: String?) -> PipelineBundle {
    var result = bundle
    for (id, branch) in opened {
      Self.overlay(branch.head, of: id, onto: &result, stack: bundle, baseID: baseID)
    }
    return result
  }

  /// Puts `head` (`nil`: the layer as stacked in `stack`) over layer `id` of `bundle`.
  package static func overlay(
    _ head: AstroImage?, of id: String, onto bundle: inout PipelineBundle, stack: PipelineBundle,
    baseID: String?
  ) {
    guard let head else {
      bundle.layers[id] = stack.layers[id]
      bundle.layerStats[id] = stack.layerStats[id]
      if id == baseID { bundle.stats = stack.stats }
      return
    }
    let measured = LayerStats.measured(head)
    bundle.layers[id] = head
    bundle.layerStats[id] = measured.keepingFit(of: stack.layerStats[id])
    if id == baseID { bundle.stats = measured.keepingFit(of: stack.stats) }
  }

  private func open(_ layerID: String, layer: AstroImage) throws -> Branch {
    let history = try History.reopen(
      directory: folder.appendingPathComponent(layerID), original: layer, header: header,
      schema: schema)
    return Branch(layerID: layerID, history: history)
  }
}
