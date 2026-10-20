/// Frames sharing a `SetKey` (`inspect.Set`), in capture order.
package struct FrameSet: Equatable, Sendable {
  package var key: SetKey
  package var frames: [CaptureFrame]
  /// Positions of `frames` in the array the set was grouped from.
  package var indices: [Int]
  /// The clip filter of a one-shot-colour light set; a projection of `Inventory.filterSets`.
  package var filterSet: FilterSet = .unknown

  /// A set of `frames` grouped from positions `indices`.
  package init(key: SetKey, frames: [CaptureFrame], indices: [Int], filterSet: FilterSet = .unknown) {
    self.key = key
    self.frames = frames
    self.indices = indices
    self.filterSet = filterSet
  }

  package var count: Int { frames.count }
  package var totalIntegrationMs: Int { frames.reduce(0) { $0 + $1.exposureMs } }

  /// Groups the typed frames of a scan (`buildSets`). Only when lights and flats span several
  /// known nights does a key carry the night, so a single-night scan keeps its legacy keys.
  package static func group(_ frames: [CaptureFrame]) -> [FrameSet] {
    let split = Night.spansSeveral(frames)
    var groups: [SetKey: [Int]] = [:]
    var order: [SetKey] = []
    for (index, frame) in frames.enumerated() where frame.type != .unknown && frame.type != .video {
      let key = SetKey(frame: frame, splitNights: split)
      if groups[key] == nil { order.append(key) }
      groups[key, default: []].append(index)
    }
    let sets = order.flatMap { key in
      TemperatureClusters.split(groups[key] ?? [], of: frames, type: key.type).map { cluster in
        var clusterKey = key
        clusterKey.tempBucketC = cluster.bucketC
        return FrameSet(key: clusterKey, frames: cluster.indices.map { frames[$0] }, indices: cluster.indices)
      }
    }
    return sets.sorted { SetKey.precedes($0.key, $1.key) }
  }
}
