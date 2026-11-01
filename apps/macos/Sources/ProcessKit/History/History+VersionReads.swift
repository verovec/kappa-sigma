package import ImageKit

// MARK: - What the Versions menu and ▶ Run read of a version (card 0159)

extension History {
  /// The image version `id` ended on: the output of its last step not undone, read from disk
  /// (the Versions menu compares the viewer with it).
  package func head(ofVersion id: String) throws -> AstroImage {
    let version = try self.version(id)
    let applied = version.steps.count - version.redo
    guard applied > 0 else { return try image(file: version.parent) }
    return try image(file: version.steps[applied - 1].file)
  }

  /// The mask step `offset` of version `id` was applied under, or `nil` when unmasked.
  package func mask(ofVersion id: String, step offset: Int) throws -> AstroImage? {
    let version = try self.version(id)
    guard version.steps.indices.contains(offset) else { throw HistoryError.noStep(offset) }
    return try version.steps[offset].mask.map { try image(file: $0) }
  }

  /// The bytes dropping version `id` frees: the files only it refers to.
  package func bytes(ofVersion id: String) throws -> Int {
    let version = try self.version(id)
    let others = versions.filter { $0.id != id }.flatMap(\.steps)
    let kept = Set(Self.files(of: steps + undone + others) + snapshots.compactMap(\.file))
    return bytes(of: Set(Self.files(of: version.steps)).subtracting(kept))
  }

  private func version(_ id: String) throws -> Version {
    guard let version = versions.first(where: { $0.id == id }) else {
      throw HistoryError.unknownVersion(id)
    }
    return version
  }
}
