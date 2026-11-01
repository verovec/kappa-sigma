import AstroStackApp
import Foundation
import RemoteKit
import TestSupport
import Testing

/// The S3 forms' bindings write into their models (cards 0150, 0152).
@MainActor
@Suite("S3 form bindings — what a field or toggle writes")
struct FormBindingTests {
  @Test(
    "export targets: On S3 makes a target on the first connection; fields write into it",
    .scratchDirectory)
  func testExportTargetsBindings() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    var services = try ExportStageModelTests.services()
    let first = UUID()
    let second = UUID()
    services.s3Connections = {
      [first, second].map {
        S3Connection(
          id: $0, name: $0.uuidString, endpoint: "https://s3.example.com", region: "",
          pathStyle: false, accessKey: "AK")
      }
    }
    let model = try ExportStageModelTests.model(
      opened, studio: try ExportStageModelTests.separated(opened), services: services)
    let on = ExportTargetsForm.s3On(model)
    #expect(!on.wrappedValue)

    on.wrappedValue = true
    #expect(model.s3?.connectionID == first && on.wrappedValue)
    ExportTargetsForm.field(model, \.bucket).wrappedValue = "exports"
    ExportTargetsForm.field(model, \.prefix).wrappedValue = "astro"
    ExportTargetsForm.connection(model).wrappedValue = second
    ExportTargetsForm.connection(model).wrappedValue = nil
    #expect(model.s3 == S3Target(connectionID: second, bucket: "exports", prefix: "astro"))
    #expect(ExportTargetsForm.field(model, \.bucket).wrappedValue == "exports")
    #expect(ExportTargetsForm.connection(model).wrappedValue == second)
    on.wrappedValue = true
    #expect(model.s3?.bucket == "exports", "turning it on again keeps the target")
    on.wrappedValue = false
    #expect(model.s3 == nil && ExportTargetsForm.field(model, \.bucket).wrappedValue == "")
  }

  @Test("S3 connection editor: fields and the path-style toggle write into the draft")
  func testConnectionEditorBindings() throws {
    let name = "fr.astrostack.tests.bindings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let model = S3ConnectionsModel(
      store: S3ConnectionStore(defaults: defaults, secrets: .inMemory()))
    #expect(S3ConnectionsSection.field(model, \.connection.name).wrappedValue == "")
    #expect(!S3ConnectionsSection.pathStyle(model).wrappedValue)

    model.add()
    S3ConnectionsSection.field(model, \.connection.name).wrappedValue = "MinIO"
    S3ConnectionsSection.field(model, \.secret).wrappedValue = "s"
    S3ConnectionsSection.pathStyle(model).wrappedValue = true

    #expect(model.draft?.connection.name == "MinIO" && model.draft?.secret == "s")
    #expect(S3ConnectionsSection.pathStyle(model).wrappedValue)
  }

  @Test(
    "without any S3 connection, « On S3 » stays off: no target on a made-up connection",
    .scratchDirectory)
  func testS3OnWithoutConnections() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    var services = try ExportStageModelTests.services()
    services.s3Connections = { [] }
    let model = try ExportStageModelTests.model(
      opened, studio: try ExportStageModelTests.separated(opened), services: services)

    ExportTargetsForm.s3On(model).wrappedValue = true

    #expect(model.s3 == nil)
  }
}
