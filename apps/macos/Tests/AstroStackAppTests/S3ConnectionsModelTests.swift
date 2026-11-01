import AstroStackApp
import Foundation
import RemoteKit
import Testing

/// Settings › S3 connections, the editing lifecycle of the model (card 0150).
@MainActor
@Suite("S3 connections model — add, edit, cancel, remove, refusals kept visible")
struct S3ConnectionsModelTests {
  @Test(
    "cancel drops the draft and its refusal; an unknown id opens nothing; no draft saves nothing")
  func testEditingLifecycle() throws {
    let name = "fr.astrostack.tests.s3model.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let model = S3ConnectionsModel(
      store: S3ConnectionStore(defaults: defaults, secrets: .inMemory()))

    model.save()
    #expect(model.connections.isEmpty && model.refusal == nil, "no draft, nothing saved")
    model.add()
    model.save()
    #expect(model.refusal == .s3Connection(.emptyName) && model.draft != nil)
    model.cancel()
    #expect(model.draft == nil && model.refusal == nil)
    model.edit(UUID())
    #expect(model.draft == nil, "an id no longer stored opens no editor")

    model.add()
    model.draft?.connection.name = "A"
    model.draft?.connection.endpoint = "https://s3.example.com"
    model.draft?.connection.accessKey = "AK"
    model.draft?.secret = "s"
    model.save()
    let id = try #require(model.connections.first?.id)
    model.refreshSecretStates()
    #expect(model.secretStates == [id: .stored])
    model.edit(id)
    model.remove(id)
    #expect(model.draft == nil, "removing the connection being edited closes its editor")
    #expect(model.connections.isEmpty && model.secretStates.isEmpty)
  }

  @Test("a Keychain refusal on remove keeps the connection and says why")
  func testRemoveRefused() throws {
    let name = "fr.astrostack.tests.s3model.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let saved = try S3ConnectionStore(defaults: defaults, secrets: .inMemory())
      .save(
        S3Connection(
          name: "A", endpoint: "https://s3.example.com", region: "", pathStyle: false,
          accessKey: "AK"),
        secret: "s")
    let denied = KeychainError(status: -25293)
    let locked = SecretStore(
      read: { _ in throw denied }, contains: { _ in throw denied }, write: { _, _ in throw denied },
      delete: { _ in throw denied })
    let model = S3ConnectionsModel(store: S3ConnectionStore(defaults: defaults, secrets: locked))

    model.refreshSecretStates()
    #expect(model.secretStates[saved.id] == .unreadable(denied))
    #expect(!model.hasSecret(saved.id))
    model.remove(saved.id)

    #expect(model.refusal == .s3Connection(.keychain(denied)))
    #expect(model.connections == [saved])
  }
}
