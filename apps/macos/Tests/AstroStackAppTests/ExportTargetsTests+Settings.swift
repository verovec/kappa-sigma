import AstroStackApp
import Foundation
import RemoteKit
import Synchronization
import TestSupport
import Testing

extension ExportTargetsTests {
  /// Card 0177: « Add an S3 connection in Settings › S3 connections first » now has its button.
  @Test(
    "testOpensS3Connections: « S3 connections… » beside the S3 target, with and without one",
    .scratchDirectory, arguments: [0, 1])
  func testOpensS3Connections(connections: Int) throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let connection = S3Connection(
      name: "Exports", endpoint: "https://s3.example.com", region: "us-east-1", pathStyle: false,
      accessKey: "AK")
    let listed = Array([connection].prefix(connections))
    var services = try ExportStageModelTests.services()
    services.s3Connections = { listed }
    let model = try ExportStageModelTests.model(
      opened, studio: try ExportStageModelTests.separated(opened), services: services)
    var asked: [SettingsTab?] = []
    let form = ExportTargetsForm(model: model, openSettings: { asked.append($0) })

    let entries = AccessibilityAuditTests.entries(form)
    form.settingsButton.press()

    #expect(entries.contains { $0.id == "fr.astrostack.settings.open.s3" }, "\(entries.map(\.id))")
    #expect(asked == [.s3])
  }
}

extension ExportTargetsTests {
  /// Review of card 0177: the form read the connections only when something else redrew it, so
  /// one added through « S3 connections… » never enabled « On S3 ».
  @Test("the stage follows Settings' connections: at once, then on every change", .scratchDirectory)
  func testFollowsConnections() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let connection = S3Connection(
      name: "Exports", endpoint: "https://s3.example.com", region: "us-east-1", pathStyle: false,
      accessKey: "AK")
    let stored = Mutex<[S3Connection]>([])
    var services = try ExportStageModelTests.services()
    services.s3Connections = { stored.withLock { $0 } }
    let model = try ExportStageModelTests.model(
      opened, studio: try ExportStageModelTests.separated(opened), services: services)
    #expect(model.s3Connections.isEmpty)

    stored.withLock { $0 = [connection] }
    #expect(model.s3Connections.isEmpty, "nothing moves until a read")
    model.reloadConnections()
    #expect(model.s3Connections == [connection])

    stored.withLock { $0 = [] }
    let (changes, writer) = AsyncStream.makeStream(of: Void.self)
    writer.yield()
    writer.finish()
    await model.followSettings(changes)
    #expect(model.s3Connections.isEmpty)
  }
}
