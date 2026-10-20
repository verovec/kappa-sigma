/// The result of scanning capture folders (`inspect.Inventory`): every classified frame, the sets
/// calibration and stacking consume, the nights, and the warnings shown to the user.
package struct Inventory: Equatable, Sendable {
  /// The scanned folder, or the common parent of several.
  package var root: String
  package var frames: [CaptureFrame]
  package var sets: [FrameSet] = []
  package var warnings: [String] = []
  package var channelDetection: ChannelDetection?
  package var colorModel: ColorModel = .mono
  /// Light set id → clip filter, for one-shot-colour scans: the durable record `sets` project.
  package var filterSets: [String: FilterSet] = [:]
  package var sessions: [SessionInfo] = []

  /// An inventory of `frames`, not yet grouped.
  package init(root: String, frames: [CaptureFrame]) {
    self.root = root
    self.frames = frames
  }

  /// Frames per type.
  package var countsByType: [FrameType: Int] {
    frames.reduce(into: [:]) { $0[$1.type, default: 0] += 1 }
  }

  /// Rebuilds the sets from the frames and re-projects the filter-set verdicts onto them.
  package mutating func regroup() {
    sets = FrameSet.group(frames)
    applyFilterSets()
  }

  /// Copies `filterSets` onto the sets (idempotent; needed after every regroup).
  mutating func applyFilterSets() {
    for index in sets.indices {
      sets[index].filterSet = filterSets[sets[index].key.id] ?? .unknown
    }
  }

  /// Drops the frames `drop` selects and regroups; returns how many were removed.
  @discardableResult
  package mutating func removeFrames(where drop: (CaptureFrame) -> Bool) -> Int {
    let before = frames.count
    frames.removeAll(where: drop)
    let removed = before - frames.count
    if removed > 0 { regroup() }
    return removed
  }

  /// Drops every frame of the listed sets (`ExcludeSets`); unknown ids are ignored.
  package mutating func excludeSets(_ ids: [String]) -> (frames: Int, sets: Int) {
    let wanted = Set(ids)
    let excluded = sets.filter { wanted.contains($0.key.id) }
    let drop = Set(excluded.flatMap(\.indices))
    guard !drop.isEmpty else { return (0, 0) }
    frames = frames.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
    regroup()
    return (drop.count, excluded.count)
  }

  /// A copy holding only the frames `keep` accepts, regrouped and re-summarized afresh (so a subset
  /// on one night collapses back to unsplit sets).
  ///
  /// Channel detection is dropped.
  package func subset(_ keep: (CaptureFrame) -> Bool) -> Self {
    var out = Self(root: root, frames: frames.filter(keep))
    out.warnings = warnings
    out.sets = FrameSet.group(out.frames)
    out.sessions = SessionInfo.summary(out.frames)
    return out
  }

  /// Warns when a multi-night split leaves light/flat frames without DATE-OBS in their own group.
  package mutating func warnUndatedSplit() {
    let undated = frames.count { $0.session.isEmpty && [.light, .flat].contains($0.type) }
    guard undated > 0 else { return }
    warnings.append(
      "\(undated) light/flat frame(s) carry no DATE-OBS — in this multi-night capture they group "
        + "separately from every night; check their headers")
  }

  /// The clip filter of a capture night, read from its light sets' verdicts: one dissenting
  /// set makes it unknown; sets without a verdict abstain.
  package func nightFilterSet(_ session: String) -> FilterSet {
    var verdict = FilterSet.unknown
    for set in sets where set.key.type == .light && set.key.session == session {
      guard let value = filterSets[set.key.id], value.isKnown else { continue }
      if verdict.isKnown && value != verdict { return .unknown }
      verdict = value
    }
    return verdict
  }
}
