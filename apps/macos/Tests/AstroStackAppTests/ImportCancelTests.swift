import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Closing the Import sheet stops its scan: a whole captures folder takes minutes at full CPU,
/// and nothing would ever read the plan of a sheet that is gone.
@MainActor
@Suite("Closing the Import sheet cancels its scan", .timeLimit(.minutes(1)))
struct ImportCancelTests {
  /// A planner that only returns once its task is cancelled.
  static let endless: ImportViewModel.Planning = { _ in
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    defer { continuation.finish() }
    for await _ in stream {}  // an AsyncStream ends when its task is cancelled
    try Task.checkCancellation()
    return try await ImportPlanningStub.empty(ImportRequest(paths: []))
  }

  /// A window whose sheet is open and scanning `/c/captures` with `endless`.
  static func scanningWindow(
    store: @escaping () -> ProjectStore? = { nil }
  ) throws -> (ProjectWindowModel, ImportViewModel) {
    let window = ProjectWindowModel(store: store, planning: { _ in endless })
    window.startImport()
    let sheet = try #require(window.importing)
    sheet.choose(folder: URL(fileURLWithPath: "/c/captures"))
    #expect(sheet.isScanning)
    return (window, sheet)
  }

  @Test("Cancel (or the sheet dismissed) stops the scan")
  func testCloseImport_cancelsScan() async throws {
    let (window, sheet) = try Self.scanningWindow()

    window.closeImport()

    #expect(window.importing == nil)
    await sheet.settled()
    #expect(!sheet.isScanning)
  }

  @Test("Add to Project stops a rescan still running", .scratchDirectory)
  func testAdd_cancelsScan() async throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("P.astrostack"))
    defer { try? project.close() }
    let (window, sheet) = try Self.scanningWindow(store: { project.store })

    window.add(ImportRequest(paths: ["/c/captures"]))

    #expect(window.importing == nil)
    await sheet.settled()
    #expect(!sheet.isScanning)
  }

  @Test("opening a new sheet stops the scan of the one it replaces")
  func testStartImport_cancelsPreviousScan() async throws {
    let (window, sheet) = try Self.scanningWindow()

    window.startImport()

    #expect(window.importing !== sheet)
    await sheet.settled()
    #expect(!sheet.isScanning)
  }
}
