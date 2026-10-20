extension Inventory {
  /// Centre pixels read per light to fingerprint it.
  static let channelSample = 200_000
  /// Below this, detection is surfaced for the user to override.
  static let lowConfidence = 0.45

  /// The camera configuration and target lights are grouped by for detection; the exposure is a
  /// per-frame signal. `filter` is empty when the filter is what is being inferred.
  private struct ConfigKey: Hashable {
    var object: String
    var gain: Int
    var offset: Int
    var tempBucket: Int
    var bin: Int
    var filter: String

    init(_ frame: CaptureFrame, filter: String = "") {
      object = frame.object
      gain = frame.gain
      offset = frame.offset
      // Go's int() truncates toward zero.
      tempBucket = frame.hasTemp ? Int(frame.tempC / 5) * 5 : 0
      bin = frame.binX
      self.filter = filter
    }
  }

  /// Fingerprints every mono light once, names unlabeled groups by wheel order, and flags
  /// wheel-transition frames on labeled groups too (`processChannels`).
  mutating func detectChannels(pixels: PixelReader, options: ChannelDetector.Options) throws {
    let lights = frames.indices.filter { frames[$0].type == .light && frames[$0].bayer.isEmpty }
    guard !lights.isEmpty else { return }
    var fingerprints: [Int: ChannelDetector.Fingerprint] = [:]
    for index in lights {
      try Task.checkCancellation()
      var print = ChannelDetector.Fingerprint(exposureMs: frames[index].exposureMs)
      if let stats = pixels.stats(frames[index].path, sample: Self.channelSample) {
        print.background = stats.median
        print.flux = stats.p90 - stats.median
        print.starRichness = stats.brightFraction
        print.noise = stats.mad
      }
      fingerprints[index] = print
    }
    detectUnlabeled(lights, fingerprints: fingerprints, options: options)
    if options.detectTransitions {
      flagLabeled(lights, fingerprints: fingerprints, options: options)
    }
  }

  private mutating func detectUnlabeled(
    _ lights: [Int], fingerprints: [Int: ChannelDetector.Fingerprint],
    options: ChannelDetector.Options
  ) {
    for group in groups(lights.filter { frames[$0].filter.isEmpty }, by: { ConfigKey(frames[$0]) })
    {
      let result = ChannelDetector.detect(samples(group, fingerprints), options: options)
      let byPath = Dictionary(result.assignments.map { ($0.path, $0) }, uniquingKeysWith: { $1 })
      for index in group {
        let assignment = byPath[frames[index].path]
        frames[index].filter = assignment?.filter ?? ""
        frames[index].classSource = .signal
        frames[index].filterConfidence = assignment?.confidence ?? 0
        frames[index].wheelTransition = assignment?.wheelTransition ?? false
      }
      record(result)
    }
  }

  private mutating func flagLabeled(
    _ lights: [Int], fingerprints: [Int: ChannelDetector.Fingerprint],
    options: ChannelDetector.Options
  ) {
    let labeled = lights.filter { !frames[$0].filter.isEmpty && frames[$0].classSource != .signal }
    for group in groups(labeled, by: { ConfigKey(frames[$0], filter: frames[$0].filter) }) {
      let flagged = Set(
        ChannelDetector.flagTransitions(samples(group, fingerprints), options: options)
          .filter(\.wheelTransition).map(\.path))
      for index in group where flagged.contains(frames[index].path) {
        frames[index].wheelTransition = true
      }
    }
  }

  /// Indices grouped by a key, groups in first-seen order.
  private func groups<Key: Hashable>(_ indices: [Int], by key: (Int) -> Key) -> [[Int]] {
    var order: [Key] = []
    var members: [Key: [Int]] = [:]
    for index in indices {
      let value = key(index)
      if members[value] == nil { order.append(value) }
      members[value, default: []].append(index)
    }
    return order.map { members[$0] ?? [] }
  }

  /// Acquisition order: DATE-OBS, else a `frameNNN` index in the name, else walk position.
  private func samples(
    _ group: [Int], _ fingerprints: [Int: ChannelDetector.Fingerprint]
  ) -> [ChannelDetector.Sample] {
    group.enumerated().map { position, index in
      let frame = frames[index]
      var order = position
      if frame.dateObsMs > 0 {
        order = frame.dateObsMs
      } else if let match = frame.path.firstMatch(of: /(?i)frame[-_]?0*(\d+)/),
        let number = Int(match.1)
      {
        order = number
      }
      return ChannelDetector.Sample(
        order: order, path: frame.path, fingerprint: fingerprints[index] ?? .init())
    }
  }

  /// Accumulates one group's detection for the UI, warning on low confidence.
  private mutating func record(_ result: ChannelDetector.Result) {
    var detection = channelDetection ?? ChannelDetection(order: result.order)
    let base = detection.runs.count
    detection.runs += result.runs.map { run in
      DetectedRun(
        filter: run.filter, count: run.count, confidence: run.confidence,
        firstFrame: run.paths.first ?? "", lastFrame: run.paths.last ?? "")
    }
    for assignment in result.assignments
    where assignment.wheelTransition && base + assignment.runIndex < detection.runs.count {
      detection.runs[base + assignment.runIndex].wheelTransitions += 1
    }
    let current = detection.overallConfidence
    detection.overallConfidence =
      current == 0 ? result.overallConfidence : min(current, result.overallConfidence)
    channelDetection = detection
    if result.overallConfidence < Self.lowConfidence {
      warnings.append(
        "channel detection low confidence (\(String(format: "%.2f", result.overallConfidence))) — "
          + "review/override the filter mapping")
    }
  }
}
