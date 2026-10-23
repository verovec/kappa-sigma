import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0098 through the window model: the Stacking stage shows what the next run needs against
/// the room left, and a run that would fill the scratch volume is refused before Siril starts.
@MainActor
@Suite("Scratch budget — estimate before Run, refuse without room")
struct ScratchBudgetTests {
  /// Three 1000×1000 mono lights of one night: two 4 MB copies each.
  nonisolated static let needed: Int64 = 3 * 2 * 1000 * 1000 * 4

  /// The lights of `StackingStageModelTests.inventory`, sized.
  nonisolated static func inventory(width: Int = 1000, height: Int = 1000) -> Inventory {
    var inventory = StackingStageModelTests.inventory(objects: ["M 31"])
    for index in inventory.frames.indices {
      (inventory.frames[index].width, inventory.frames[index].height) = (width, height)
    }
    inventory.regroup()
    return inventory
  }

  /// A scanned project, the runs it started and its scratch folder.
  struct Fixture {
    let project: ProjectPackage
    let window: ProjectWindowModel
    let ran: Recorded<PreprocessRequest>
    let work: URL
  }

  /// A saved project scanned once, whose scratch volume has `room` bytes left.
  static func fixture(room: Int64?, inventory: Inventory = inventory()) async throws -> Fixture {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    let ran = Recorded<PreprocessRequest>()
    let work = scratch.appendingPathComponent("work")
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      services: { _ in
        ImportServices(planning: { request in
          ImportPlan(inventory: inventory, library: [], request: request)
        })
      },
      runs: RunServices(
        run: ProjectTests.fakeRun(ran), now: { ProjectTests.start }, scratch: work,
        timeZone: .gmt, room: { _ in room }))
    window.add(ImportRequest(paths: ["/c/M 31"]))
    window.rescan()
    await window.scanSettled()
    return Fixture(project: project, window: window, ran: ran, work: work)
  }

  @Test(
    "without room the reason is shown and the run never starts; with room it starts",
    .scratchDirectory,
    arguments: [(Int64?.some(needed - 1), false), (needed, true), (nil, true)])
  func testRefusesWithoutRoom(room: Int64?, started: Bool) async throws {
    let fixture = try await Self.fixture(room: room)
    let (project, window, ran, work) = (fixture.project, fixture.window, fixture.ran, fixture.work)
    defer { try? project.close() }
    let budget = try #require(window.scratchBudget, "a scan with sized lights is estimated")
    #expect(budget == ScratchBudget(neededBytes: Self.needed, roomBytes: room, folder: work))
    #expect(budget.fits == started)

    window.startRun()
    await window.run?.settled()
    #expect(ran.all.count == (started ? 1 : 0), "Siril never starts on a volume too small")
    guard !started else { return }
    let refusal = UserFacingError.preprocess(
      .scratchFull(
        neededBytes: Self.needed, availableBytes: try #require(room), folder: work.path))
    #expect(window.run?.phase == .failed(refusal))
    #expect(try project.store.stacks().isEmpty)
  }

  @Test("no sized light in the scan: no line, nothing refused on a guess", .scratchDirectory)
  func testUnsizedScanShowsNothing() async throws {
    let fixture = try await Self.fixture(room: 0, inventory: Self.inventory(width: 0, height: 0))
    let (project, window, ran) = (fixture.project, fixture.window, fixture.ran)
    defer { try? project.close() }
    #expect(window.scratchBudget == nil)
    window.startRun()
    await window.run?.settled()
    #expect(ran.all.count == 1)
  }

  @Test("gigabytes shown: the need rounded up, the room rounded down")
  func testRoundingNeverFlatters() {
    #expect(ScratchBudget.gigabytesUp(80_400_000_001) == 81)
    #expect(ScratchBudget.gigabytesUp(81_000_000_000) == 81)
    #expect(ScratchBudget.gigabytesDown(40_999_999_999) == 40)
  }
}
