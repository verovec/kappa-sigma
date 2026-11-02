/// A line process with « Other line » slots (card 0164): line injection and emission screens
/// share the slots' panel rules here, once.
package protocol LineSlotProcess: ImageProcess {}

extension LineSlotProcess {
  /// The 0135 rule (`layerRowsHidden`) for every row except the slot pickers: picker k shows once
  /// the bundle has k custom line layers, or while it names one (`EmissionLine.hiddenSlotPickers`).
  package static func hiddenParameters(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    layerRowsHidden(params, layerIDs: layerIDs)
      .subtracting(EmissionLine.slots.map(EmissionLine.slotLayerID))
      .union(EmissionLine.hiddenSlotPickers(params, layerIDs: layerIDs))
  }

  /// A slot lists the bundle's custom line layers; any other layer parameter, its grammar's.
  package static func layerOptions(for spec: ParamSpec, planes: [String: Int]) -> [String] {
    EmissionLine.slotOptions(for: spec, planes: planes)
      ?? LayerPlane.options(for: spec, planes: planes)
  }
}
