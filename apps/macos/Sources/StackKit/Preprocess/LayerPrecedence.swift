/// Which file of a channel is its layer: the one implementation shared by the bundle writer
/// (0048) and the legacy-run builder (0043).
///
/// Legacy `reconstructChannelsFromDisk` (`internal/pipeline/refine.go:214`): `combine_` >
/// `aligned_` > `master_` > `syn_`; this app's runs add `trim_` (edge-cropped) on top.
package enum LayerPrecedence {
  /// Stage prefixes, best first.
  package static let stages = ["trim", "combine", "aligned", "master", "syn"]

  /// The stage of a file's base name (`aligned_RGB` → `aligned`), or `nil` without one.
  package static func stage(of base: String) -> String? {
    guard let underscore = base.firstIndex(of: "_") else { return nil }
    let stage = String(base[..<underscore])
    return stages.contains(stage) ? stage : nil
  }

  /// The channel tag of a staged base name (`aligned_RGB-dualband` → `RGB-dualband`).
  package static func tag(of base: String) -> String? {
    guard stage(of: base) != nil, let underscore = base.firstIndex(of: "_") else { return nil }
    return String(base[base.index(after: underscore)...])
  }

  /// The best of `bases` (extension-less file names) for channel `tag`, with its stage.
  package static func best(for tag: String, among bases: Set<String>) -> (
    base: String, stage: String
  )? {
    for stage in stages where bases.contains("\(stage)_\(tag)") {
      return ("\(stage)_\(tag)", stage)
    }
    return nil
  }
}
