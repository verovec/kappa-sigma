import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0190: a night imported from a bucket is a capture night like any other — the project
/// plans it, Run is offered, and the run's request carries the bucket its frames are read from.
@MainActor
@Suite("ProjectWindowModel — a bucket night is planned and stacked")
struct ProjectWindowModelRemoteRunTests {
  nonisolated static let night = "s3://astro/M31/2026-10-18"

  /// Three lights of M 31, two darks and a bias, read from the bucket night.
  nonisolated static func inventory() -> Inventory {
    var inventory = StackingStageModelTests.inventory(objects: ["M 31"])
    for index in inventory.frames.indices {
      let name = URL(fileURLWithPath: inventory.frames[index].path).lastPathComponent
      inventory.frames[index].path = "\(night)/\(index)_\(name)"
    }
    inventory.root = night
    inventory.regroup()
    return inventory
  }

  /// What a window over a saved project heard: the requests planned, the sources whose buckets
  /// a run looked up, and the requests run.
  struct Heard {
    /// The requests the project's planner was asked (Rescan, Run).
    let planned = Recorded<ImportRequest>()
    /// The prefixes read on their own (the Import sheet, each bucket row).
    let readAlone = Recorded<ImportRequest>()
    let lookedUp = Recorded<[ProjectSource]>()
    let ran = Recorded<PreprocessRequest>()
  }

  /// A saved project and its window, the bucket night added through the Import sheet.
  static func project(_ heard: Heard) async throws -> (ProjectPackage, ProjectWindowModel) {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    let plan: ImportViewModel.Planning = { request in
      heard.planned.append(request)
      return ImportPlan(inventory: inventory(), library: [], request: request)
    }
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      services: { _ in
        ImportServices(
          planning: ImportViewModel.reporting(plan),
          remotePlanning: { _, request, _ in
            heard.readAlone.append(request)
            return ImportPlan(inventory: inventory(), library: [], request: request)
          },
          browsing: { _, _, _ in [] })
      },
      runs: RunServices(
        run: ProjectTests.fakeRun(heard.ran), now: { ProjectTests.start },
        scratch: scratch.appendingPathComponent("work"), timeZone: .gmt,
        buckets: { sources in
          heard.lookedUp.append(sources)
          var buckets = RunBuckets()
          buckets.stores = [
            RemoteObjectStore(bucket: "astro", list: { _ in [] }, get: { _, _ in Data() })
          ]
          return buckets
        }))
    window.startImport()
    let sheet = try #require(window.importing)
    let bucket = try #require(sheet.bucket)
    bucket.connectionID = ProjectWindowModelBucketTests.connection.id
    bucket.bucket = "astro"
    bucket.enter("M31/2026-10-18/")
    sheet.choose(bucket: try #require(bucket.target))
    await sheet.settled()
    window.add(sheet.request)
    await window.scanSettled()
    return (project, window)
  }

  @Test(
    "testRemoteOnlyProject_CanRun: a bucket night alone is a night to stack",
    .scratchDirectory)
  func testRemoteOnlyProject_CanRun() async throws {
    let heard = Heard()
    let (project, window) = try await Self.project(heard)
    defer { try? project.close() }

    #expect(window.sources.map(\.kind) == [.remoteNight])
    #expect(window.nightPaths == [Self.night], "what the stages read as the capture nights")
    #expect(window.canRun && window.runBlocker == nil, "never « Import a capture night »")
    #expect(window.integration != nil, "the sheet's plan is the project's scan")
    #expect(window.remoteState(of: Self.night)?.lights == 3)
  }

  @Test("testRunBlocker: the first reason Run is not offered", .scratchDirectory)
  func testRunBlocker() async throws {
    let empty = try ProjectWindowModelTests.package()
    defer { try? empty.close() }
    let none = ProjectWindowModel(
      store: { empty.store },
      services: { _ in ImportServices(planning: ImportPlanningStub.empty) })
    #expect(none.runBlocker == .noNight)

    try empty.store.addSource(kind: .legacyRun, path: "/runs/M31/78")
    none.refresh()
    #expect(none.runBlocker == .legacyRunsOnly, "an imported run is shown, never stacked")

    none.add(ImportRequest(paths: ["/c/M31"]))
    #expect(none.runBlocker == nil, "a night to stack: nothing holds Run back")
  }

  @Test(
    "a bucket night counts for the kept profile and for what a re-stack adds",
    .scratchDirectory)
  func testRemoteNight_CountsAsANight() async throws {
    let heard = Heard()
    let (project, window) = try await Self.project(heard)
    defer { try? project.close() }
    let galaxy = ProjectWindowModelProfileTests.galaxy

    try project.store.setProfile(galaxy, kind: .remoteNight, path: Self.night)
    window.refresh()
    #expect(window.knobs.profile?.id == galaxy, "the profile its import kept")

    window.startRun()
    await ProjectScopeTests.queueSettled(window)
    _ = try project.store.addSource(
      remote: ProjectWindowModelBucketTests.connection.id.uuidString, bucket: "astro",
      prefix: "M31/2026-10-19")
    window.refresh()
    window.rescan()
    await window.scanSettled()
    #expect(window.restackPlan?.added == 1, "a bucket night imported since the last stack")
    #expect(window.knobs.profile == nil, "a night that kept no profile counts")
  }

  @Test("Rescan plans the bucket night with the run's request", .scratchDirectory)
  func testRescan_PlansTheRemoteNight() async throws {
    let heard = Heard()
    let (project, window) = try await Self.project(heard)
    defer { try? project.close() }
    #expect(heard.planned.all.isEmpty, "until now the sheet alone read the prefix")

    window.rescan()
    await window.scanSettled()

    #expect(
      heard.planned.all.map(\.paths) == [[Self.night]],
      "the project's planner plans the bucket night, as it plans a folder")
    #expect(window.integration != nil && window.error == nil)
  }

  @Test(
    "testRun_RemoteNight_HandsStoresToTheRequest: the run reads the bucket its frames name",
    .scratchDirectory)
  func testRun_RemoteNight_HandsStoresToTheRequest() async throws {
    let heard = Heard()
    let (project, window) = try await Self.project(heard)
    defer { try? project.close() }

    window.startRun()
    await ProjectScopeTests.queueSettled(window)

    #expect(window.error == nil)
    let request = try #require(heard.ran.all.first)
    #expect(request.remoteStores.map(\.bucket) == ["astro"])
    #expect(request.inventory.frames.allSatisfy { $0.path.hasPrefix(Self.night + "/") })
    #expect(request.inventory.frames.count { $0.type == .light } == 3)
    #expect(heard.lookedUp.all.first?.map(\.path) == [Self.night], "only the buckets it reads")
    #expect(try project.store.stacks().count == 1)
  }
}
