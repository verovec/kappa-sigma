// MARK: - What the combined image holds (card 0131)

extension StudioSession {
  /// The layers of `layerIDs` the image holds after the main `steps`: what the Studio says under
  /// « Combined », so a step reading the head (colour calibration) is not taken to see the lines
  /// before they are injected.
  ///
  /// The base layer (the history starts from it), then each step's `layersMerged` — added, or
  /// replacing everything before for a process whose input only sets the size (`replacesInput`,
  /// the channel combination). Never `layersRead`: a layer read for a continuum or rewritten
  /// beside the head is not in the image.
  package static func combinedLayers(
    after steps: [(processID: String, params: ParamSet)], layerIDs: Set<String>,
    registry: ProcessRegistry
  ) -> Set<String> {
    var holds = Set([baseLayerID(layerIDs)].compactMap(\.self))
    for step in steps {
      guard let type = registry.type(id: step.processID) else { continue }
      let merged = type.layersMerged(step.params, layerIDs: layerIDs)
      holds = type.replacesInput ? merged : holds.union(merged)
    }
    return holds
  }
}
