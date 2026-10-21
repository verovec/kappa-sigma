import Foundation
import ProjectKit
import TestSupport
import Testing

@Suite("ProjectStore: the project.db schema and its typed accessors")
struct ProjectStoreTests {
  static let applicationTables = [
    "calibration_masters", "history_steps", "images", "pipelines", "project_settings", "recipes",
    "snapshots", "sources", "stack_sources", "stacks", "user_profiles",
  ]

  static func newPackage(_ name: String = "M31") throws -> ProjectPackage {
    try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("\(name).astrostack"))
  }

  @Test(
    "up then down leaves an empty schema; versions and ms timestamps are recorded",
    .scratchDirectory)
  func testMigrateUpDown() throws {
    let package = try Self.newPackage()
    defer { try? package.close() }
    let store = package.store
    let before = Int64(Date().timeIntervalSince1970 * 1000)

    #expect(try store.tableNames() == (Self.applicationTables + ["schema_migrations"]).sorted())
    let applied = try store.appliedMigrations()
    #expect(applied.map(\.version) == [1, 2, 3])
    #expect(applied.map(\.name) == ["init", "calibration_masters", "project_settings"])

    try store.migrate(to: 0)
    #expect(try store.tableNames() == ["schema_migrations"])
    #expect(try store.appliedMigrations().isEmpty)

    try store.migrate(to: nil)
    let reapplied = try #require(store.appliedMigrations().first)
    let after = Int64(Date().timeIntervalSince1970 * 1000)
    #expect((before...after).contains(reapplied.appliedAtMs), "applied_at is int64 ms")
    #expect(try store.tableNames() == (Self.applicationTables + ["schema_migrations"]).sorted())
  }

  @Test("stacks lists every stack oldest first, each with its sources", .scratchDirectory)
  func testStacksListed() throws {
    let package = try Self.newPackage()
    defer { try? package.close() }
    let store = package.store
    #expect(try store.stacks().isEmpty)
    let night = try store.addSource(kind: .night, path: "/captures/M31-DB")
    let other = try store.addSource(kind: .night, path: "/captures/M31-BB")
    let first = try store.addStack(
      bundlePath: "stacks/A", sourceIDs: [other.id, night.id], paramsJSON: "{}")
    let second = try store.addStack(bundlePath: "stacks/B", sourceIDs: [], paramsJSON: "{}")

    #expect(try store.stacks() == [first, second])
    #expect(try store.stacks().first?.sourceIDs == [night.id, other.id])
  }

  @Test("a stack and its images are recorded together, or not at all", .scratchDirectory)
  func testStackWithImagesIsOneTransaction() throws {
    let package = try Self.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(
      bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}", imageRoles: ["Ha", "OIII", "RGB"])
    #expect(try store.images(stackID: stack.id).map(\.role) == ["Ha", "OIII", "RGB"])

    #expect(throws: (any Error).self) {
      try store.addStack(bundlePath: "stacks/B", sourceIDs: [9_999], paramsJSON: "{}")
    }
    #expect(try store.stacks() == [stack], "an unknown source rolls the whole stack back")
  }

  struct RoundTrip: Sendable, CustomTestStringConvertible {
    let role: String
    let sourceKind: ProjectSource.Kind
    let steps: Int
    var testDescription: String { "\(role), \(steps) step(s), \(sourceKind)" }
  }

  @Test(
    "source → stack → image → history → snapshot survives a reopen", .scratchDirectory,
    arguments: [
      RoundTrip(role: "rgb", sourceKind: .night, steps: 3),
      RoundTrip(role: "L", sourceKind: .legacyRun, steps: 1),
      RoundTrip(role: "Ha", sourceKind: .night, steps: 5),
    ])
  func testStackImageHistoryRoundTrip(_ trip: RoundTrip) throws {
    let package = try Self.newPackage()
    let store = package.store
    let source = try store.addSource(kind: trip.sourceKind, path: "/captures/M31-DB/lights")
    let stack = try store.addStack(
      bundlePath: "stacks/1", sourceIDs: [source.id], paramsJSON: #"{"preset":"deepsky"}"#)
    let image = try store.addImage(stackID: stack.id, role: trip.role)
    var steps: [HistoryStep] = []
    for ordinal in 1...trip.steps {
      steps.append(
        try store.appendHistoryStep(
          imageID: image.id, processID: "stretch.mtf", paramsJSON: #"{"midtone":0.\#(ordinal)}"#,
          output: .init(path: "history/\(ordinal).fits", bytes: Int64(ordinal) * 1_000),
          contentHash: String(repeating: "\(ordinal % 10)", count: 64)))
    }
    let snapshot = try store.addSnapshot(imageID: image.id, name: "before HDR", stepID: steps[0].id)
    let written = try Self.dump(store, stackID: stack.id, imageID: image.id)
    try package.close()

    let reopened = try ProjectPackage.open(at: package.url)
    defer { try? reopened.close() }
    let read = try Self.dump(reopened.store, stackID: stack.id, imageID: image.id)
    #expect(read == written)
    #expect(read.history.map(\.ordinal) == Array(1...trip.steps))
    #expect(read.images.first?.headStepID == steps.last?.id)
    #expect(read.snapshots == [snapshot])
    #expect(read.stack.sourceIDs == [source.id])
  }

  struct Dump: Equatable {
    let sources: [ProjectSource]
    let stack: ProjectStack
    let images: [ProjectImage]
    let history: [HistoryStep]
    let snapshots: [ImageSnapshot]
  }

  static func dump(_ store: ProjectStore, stackID: Int64, imageID: Int64) throws -> Dump {
    Dump(
      sources: try store.sources(), stack: try #require(try store.stack(id: stackID)),
      images: try store.images(stackID: stackID), history: try store.history(imageID: imageID),
      snapshots: try store.snapshots(imageID: imageID))
  }

  @Test("the disk budget sums history outputs; deleting a step drops its file", .scratchDirectory)
  func testDiskBudget() throws {
    let package = try Self.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(bundlePath: "stacks/1", sourceIDs: [], paramsJSON: "{}")
    let image = try store.addImage(stackID: stack.id, role: "rgb")
    #expect(try store.diskBudgetBytes() == 0)

    let sizes: [Int64] = [22_000_000, 0, 1_500]
    var steps: [HistoryStep] = []
    for (index, size) in sizes.enumerated() {
      steps.append(
        try store.appendHistoryStep(
          imageID: image.id, processID: "p\(index)", paramsJSON: "{}",
          output: size > 0 ? .init(path: "history/\(index).fits", bytes: size) : nil,
          contentHash: nil))
    }
    #expect(try store.diskBudgetBytes() == 22_001_500)

    try store.deleteHistoryStep(id: steps[0].id)
    #expect(try store.diskBudgetBytes() == 1_500)
    #expect(try !store.history(imageID: image.id).contains { $0.outputPath == "history/0.fits" })
  }

  @Test(
    "deleting the head moves it back to the previous step and returns the freed file",
    .scratchDirectory)
  func testProjectStore_deleteHistoryStep_head() throws {
    let package = try Self.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(bundlePath: "stacks/1", sourceIDs: [], paramsJSON: "{}")
    let image = try store.addImage(stackID: stack.id, role: "rgb")
    var steps: [HistoryStep] = []
    for ordinal in 1...3 {
      steps.append(
        try store.appendHistoryStep(
          imageID: image.id, processID: "p", paramsJSON: "{}",
          output: .init(path: "history/\(ordinal).fits", bytes: 10), contentHash: nil))
    }

    let freed = try store.deleteHistoryStep(id: steps[2].id)
    #expect(freed == HistoryStep.Output(path: "history/3.fits", bytes: 10))
    #expect(try store.images(stackID: stack.id).first?.headStepID == steps[1].id)

    let middle = try store.deleteHistoryStep(id: steps[0].id)
    #expect(middle?.path == "history/1.fits")
    #expect(try store.images(stackID: stack.id).first?.headStepID == steps[1].id)
  }

  @Test(
    "a source path is recorded once, whatever its spelling", .scratchDirectory,
    arguments: [
      "/captures/M31-DB/lights/", "/captures/M31-DB/./lights", "/captures/M31-DB/x/../lights",
    ])
  func testProjectStore_addSource_idempotent(_ spelling: String) throws {
    let package = try Self.newPackage()
    defer { try? package.close() }
    let first = try package.store.addSource(kind: .night, path: "/captures/M31-DB/lights")
    let again = try package.store.addSource(kind: .night, path: spelling)
    #expect(again == first)
    #expect(try package.store.sources().count == 1)
  }

  @Test("a step a snapshot points to cannot be deleted", .scratchDirectory)
  func testProjectStore_deleteHistoryStep_keepsSnapshots() throws {
    let package = try Self.newPackage()
    defer { try? package.close() }
    let store = package.store
    let stack = try store.addStack(bundlePath: "stacks/1", sourceIDs: [], paramsJSON: "{}")
    let image = try store.addImage(stackID: stack.id, role: "rgb")
    let step = try store.appendHistoryStep(
      imageID: image.id, processID: "p", paramsJSON: "{}", output: nil, contentHash: nil)
    _ = try store.addSnapshot(imageID: image.id, name: "keep", stepID: step.id)

    #expect(throws: (any Error).self) { try store.deleteHistoryStep(id: step.id) }
    #expect(try store.history(imageID: image.id).map(\.id) == [step.id])
  }

  @Test("the 0040 document round trip still passes on the migrated schema", .scratchDirectory)
  func testPackageDocumentOpensOnMigratedDB() throws {
    let package = try Self.newPackage()
    try package.store.addSource(kind: .night, path: "/captures/x")
    try package.save()
    try package.close()

    let reopened = try ProjectPackage.open(at: package.url)
    #expect(try reopened.store.appliedMigrations().map(\.version) == [1, 2, 3])
    #expect(try reopened.store.sources().count == 1)
    try reopened.close()
    let items = try FileManager.default.contentsOfDirectory(atPath: package.url.path)
    #expect(items == ["project.db"])
  }
}
