import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// The Données stage's scan (0078): the window keeps the last plan (the sheet's on Add, or a
/// Rescan the user asks for, never one on open), and its coverage feeds the journey.
@MainActor
@Suite("Données scan — the window's last scan, rescan on demand, coverage into the journey")
struct DataScanTests {
  /// 36 lights of one night with no calibration at all: one light set with a gap.
  nonisolated static func gapPlan(_ request: ImportRequest) -> ImportPlan {
    let frames = (0..<36).map { index in
      var frame = CaptureFrame(path: "/c/M31-DB/light_\(index).fits")
      frame.type = .light
      frame.filter = "RGB"
      frame.exposureMs = 300_000
      frame.session = "2026-09-22"
      return frame
    }
    var inventory = Inventory(root: request.paths.first ?? "", frames: frames)
    inventory.sets = [
      FrameSet(
        key: SetKey(type: .light, filter: "RGB", exposureMs: 300_000, color: true),
        frames: frames, indices: Array(frames.indices))
    ]
    return ImportPlan(inventory: inventory, library: [], request: request)
  }

  /// Records what each scan was asked for.
  final class Recorder: Sendable {
    private let recorded = Mutex<[ImportRequest]>([])
    var requests: [ImportRequest] { recorded.withLock { $0 } }
    func append(_ request: ImportRequest) { recorded.withLock { $0.append(request) } }
  }

  static func window(_ project: ProjectPackage, recorder: Recorder = Recorder())
    -> ProjectWindowModel
  {
    ProjectWindowModel(
      store: { project.store },
      planning: { _ in
        { request in
          recorder.append(request)
          return gapPlan(request)
        }
      })
  }

  @Test("opening a project scans nothing; without sources a rescan does nothing", .scratchDirectory)
  func testNoScanOnOpen() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    window.rescan()
    await window.scanSettled()
    #expect(window.scan == nil)
    #expect(window.isScanning == false)
    #expect(recorder.requests.isEmpty)
    #expect(window.statuses[.calibration] == .unavailable(.needsSources))
  }

  @Test(
    "a rescan scans the recorded sources and its gaps reach the Calibration stage",
    .scratchDirectory)
  func testRescanFeedsCoverage() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    #expect(window.statuses[.calibration] == .ready, "no scan yet: nothing is known")

    window.rescan()
    #expect(window.isScanning)
    await window.scanSettled()
    #expect(recorder.requests.map(\.paths) == [["/c/M31-DB"]])
    #expect(window.isScanning == false)
    #expect(window.integration?.frames == 36)
    #expect(window.coverage?.gaps == 1)
    #expect(window.statuses[.calibration] == .attention(1))
  }

  @Test("Add keeps the sheet's plan: the stage shows it without scanning again", .scratchDirectory)
  func testAddKeepsSheetPlan() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    window.startImport()
    let sheet = try #require(window.importing)
    sheet.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    await sheet.settled()
    window.add(sheet.request)
    #expect(recorder.requests.count == 1, "only the sheet scanned")
    #expect(window.scan == sheet.plan)
    #expect(window.statuses[.calibration] == .attention(1))
  }

  @Test(
    "a second import's plan covers only its own folder: the stale scan is dropped, not shown",
    .scratchDirectory)
  func testPartialPlanIsNotAdopted() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = Self.window(project)
    for folder in ["/c/M31-DB", "/c/M31-BB"] {
      window.startImport()
      let sheet = try #require(window.importing)
      sheet.choose(folder: URL(fileURLWithPath: folder))
      await sheet.settled()
      window.add(sheet.request)
    }
    #expect(window.sources.count == 2)
    #expect(window.scan == nil, "M31-BB's plan alone would hide M31-DB's gaps")
    #expect(window.statuses[.calibration] == .ready)
  }

  @Test("a rescan of the same sources keeps the user's import choices", .scratchDirectory)
  func testRescanKeepsImportChoices() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let recorder = Recorder()
    let window = Self.window(project, recorder: recorder)
    window.startImport()
    let sheet = try #require(window.importing)
    sheet.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    await sheet.settled()
    sheet.mapFilter("RGB", to: "ignore")
    await sheet.settled()
    window.add(sheet.request)

    window.rescan()
    await window.scanSettled()
    #expect(recorder.requests.last?.filterMap == ["RGB": "ignore"])
  }

  @Test(
    "a rescan once the document is closed says so instead of planning without a library",
    .scratchDirectory)
  func testRescanClosedProject() throws {
    let project = try ProjectWindowModelTests.package()
    let store = project.store
    var open = true
    let window = ProjectWindowModel(
      store: { open ? store : nil }, planning: { _ in { Self.gapPlan($0) } })
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    try project.close()
    open = false
    window.rescan()
    #expect(window.error == .projectClosed)
    #expect(window.isScanning == false)
  }

  @Test("cancelling stops the scan and keeps the previous result", .scratchDirectory)
  func testCancelKeepsPrevious() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store },
      planning: { _ in
        { _ in
          // A scan that only ends when cancelled: the stream never yields.
          let (stream, continuation) = AsyncStream<Void>.makeStream()
          for await _ in stream {}
          continuation.finish()
          throw CancellationError()
        }
      })
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.rescan()
    window.cancelScan()
    await window.scanSettled()
    #expect(window.isScanning == false)
    #expect(window.scan == nil)
    #expect(window.error == nil, "a cancel is not an error")
  }

  @Test("a scan that fails is reported, never silent", .scratchDirectory)
  func testScanFailure() async throws {
    struct Unreadable: Error {}
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store }, planning: { _ in { _ in throw Unreadable() } })
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.rescan()
    await window.scanSettled()
    #expect(window.isScanning == false)
    #expect(window.error != nil)
  }
}
