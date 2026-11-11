import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0190: a night whose lights are on this Mac and whose calibration is in the bucket — three
/// prefixes, each a source of the project — is planned as one capture by the project's planner
/// (`ImportPlanning.plan`) and stacks to the masters of the same night read from disk alone.
extension RemotePipelineLiveTests {
  @Test(
    "testSplitNightEqualsLocal: lights on disk, calibration prefixes in the bucket, same masters",
    .scratchDirectory)
  func testSplitNightEqualsLocal() async throws {
    try await Night.with { night in try await Self.splitEqualsLocal(night) }
  }

  /// The local run of `night`, then the run of its lights folder with the bucket's calibration
  /// prefixes, compared.
  static func splitEqualsLocal(_ night: Night) async throws {
    let local = try InventoryBuilder().scan(paths: [night.input.path])
    _ = try await night.run(local, "S_local")

    let project = try ProjectPackage.create(
      at: night.root.appendingPathComponent("S-\(UUID().uuidString).astrostack"))
    defer { try? project.close() }
    let connection = UUID()
    var paths = [night.input.appendingPathComponent("lights").path]
    _ = try project.store.addSource(kind: .night, path: paths[0])
    for folder in ["flats", "darks", "bias"] {
      let source = try project.store.addSource(
        remote: connection.uuidString, bucket: night.live.bucket, prefix: night.prefix + folder)
      paths.append(source.path)
    }
    let library = night.root.appendingPathComponent("library-\(UUID().uuidString)")
    let plan = try await ImportPlanning.plan(
      ImportRequest(paths: paths), store: project.store,
      index: LibraryIndex(store: project.store, folder: library), timeZone: .current,
      client: { [client = night.client] _ in client })
    #expect(
      Self.counts(plan.inventory) == Self.counts(local),
      "one capture: the sets of the night, wherever each frame is read from")
    #expect(plan.calibration.allSatisfy { !$0.hasGap }, "the bucket's masters serve the lights")

    let downloads = Downloads()
    let client = night.client
    let buckets = await ImportPlanning.runStores(try project.store.sources()) { _ in client }
    #expect(buckets.refusals.isEmpty)
    _ = try await night.run(
      plan.inventory, "S_split", stores: buckets.stores.map(downloads.counting))

    let reference = try Self.masterDigests(in: night.root.appendingPathComponent("out-S_local"))
    #expect(!reference.isEmpty, "the local run wrote masters")
    #expect(
      try Self.masterDigests(in: night.root.appendingPathComponent("out-S_split")) == reference,
      "same frames, same scripts, same masters")
    #expect(!downloads.calibration.isEmpty, "the calibration frames came from the bucket")
    #expect(
      downloads.keys.withLock { $0 }.allSatisfy { !$0.contains("/lights/") },
      "the lights were read where they are, on this Mac")
  }
}
