extension ImportPlan {
  /// The library masters of the role of `cell`, as the matcher sees each one alone for the light
  /// set of `channel`: chosen first, then strict matches, then forced-only ones, then other sensors.
  package func alternatives(for cell: Cell, of channel: Channel) -> [MasterAlternative] {
    guard let set = inventory.sets.first(where: { $0.key == channel.key }) else { return [] }
    let ref = LightRef(set, in: inventory)
    let type = Self.masterType(cell.role)
    // A -opt dark is applied only with a bias: give every dark the library's biases.
    let biases = library.filter { $0.type == .bias }
    let candidates = library.filter { $0.type == type }
    // One header read per master: the guard runs once over the whole list.
    let guarded = DimensionGuard.keepMatching(candidates, lightPath: set.frames.first?.path ?? "")
    let sameSensor = Set(guarded.masters.map(\.path))
    let applied = Self.isApplied(cell.status) ? cell.master?.path : nil
    let rated = candidates.compactMap { master -> MasterAlternative? in
      guard sameSensor.contains(master.path) else {
        return MasterAlternative(master: master, verdict: .otherSensor(guarded.note ?? ""))
      }
      let pool = [master] + (type == .dark ? biases : [])
      let picks = { (force: Bool) in
        CalibrationMatcher.match(ref, masters: pool, force: force).master(cell.role)?.path
          == master.path
      }
      if master.path == applied {
        return MasterAlternative(master: master, verdict: .chosen)
      }
      if picks(false) { return MasterAlternative(master: master, verdict: .matches) }
      if picks(true) { return MasterAlternative(master: master, verdict: .needsForce) }
      return nil
    }
    return rated.sorted { Self.rank($0.verdict) < Self.rank($1.verdict) }
  }

  /// The capture set the master of `cell` stands for (`satisfies`): what "Rebuild" stacks.
  package func sourceSet(of cell: Cell) -> FrameSet? {
    guard let master = cell.master else { return nil }
    return inventory.sets.first { $0.key.type != .light && master.satisfies($0.key) }
  }

  private static func isApplied(_ status: Status) -> Bool {
    switch status {
    case .library, .build: true
    case .excluded, .missing: false
    }
  }

  private static func masterType(_ role: CalibrationRole) -> MasterType {
    switch role {
    case .dark: .dark
    case .flat: .flat
    case .bias: .bias
    }
  }

  private static func rank(_ verdict: MasterAlternative.Verdict) -> Int {
    switch verdict {
    case .chosen: 0
    case .matches: 1
    case .needsForce: 2
    case .otherSensor: 3
    }
  }
}
