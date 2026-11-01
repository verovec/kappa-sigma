import AppKit
import AstroStackApp
import Foundation
import RemoteKit
import SwiftUI
import Testing

extension SettingsTests {
  @Test(
    "testS3ConnectionsSection: list, add/edit/remove, masked secret, Test line (card 0150)",
    arguments: ["en", "fr"])
  func testS3ConnectionsSection(_ language: String) async throws {
    let name = "fr.astrostack.tests.settings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let secrets = SecretStore.inMemory()
    let transport = HTTPTransport(
      send: { _ in HTTPResponse(status: 200, body: Data("<ListBucketResult/>".utf8)) },
      download: { _, _, _ in HTTPResponse(status: 500) })
    let model = S3ConnectionsModel(
      store: S3ConnectionStore(defaults: defaults, secrets: secrets), transport: { transport })
    let locale = Locale(identifier: language)

    func host() -> NSSize {
      let view = SettingsView(
        setting: LanguageSetting(defaults: defaults, domain: name), relaunch: {}, s3: model)
      let host = NSHostingView(rootView: view.environment(\.locale, locale))
      host.layoutSubtreeIfNeeded()
      return host.fittingSize
    }

    // Empty list, then the add form (the secret field empty, a refusal shown).
    #expect(host().width >= 460)
    model.add()
    model.draft?.connection.name = "Exports"
    model.draft?.connection.endpoint = "http://s3.example.com"
    model.draft?.connection.accessKey = "AK"
    model.draft?.secret = "never-shown"
    model.save()
    #expect(model.refusal == .s3Connection(.insecureEndpoint("http://s3.example.com")))
    #expect(host().height > 0)
    model.draft?.connection.endpoint = "https://s3.fr-par.scw.cloud"
    model.save()
    #expect(model.draft == nil && model.refusal == nil)
    let id = try #require(model.connections.first?.id)
    #expect(model.hasSecret(id))

    // Edit: the secret field starts empty, saving keeps the stored secret.
    model.edit(id)
    #expect(model.draft?.secret == "", "the stored secret is never shown back")
    model.draft?.connection.pathStyle = true
    model.save()
    #expect(model.connections.first?.pathStyle == true)
    #expect(try secrets.read(id.uuidString) == "never-shown")

    // Test line, laid out with its result, then removal.
    model.testBucket = "astro"
    await model.test()
    #expect(model.testResult == .ok(count: 0))
    #expect(host().width >= 460)
    model.remove(id)
    #expect(model.connections.isEmpty && model.testConnection == nil)
    #expect(try secrets.read(id.uuidString) == nil)
    #expect(SettingHelp.ids.contains(SettingHelp.s3Connections))
  }

  @Test(
    "testS3ResultLines: S3's text as sent, a count, « at least » for a full page",
    arguments: ["en", "fr"])
  func testS3ResultLines(_ language: String) {
    let locale = Locale(identifier: language)
    #expect(
      S3ConnectionsSection.resultLine(.failed("S3 403 AccessDenied: x"), locale: locale)
        == "S3 403 AccessDenied: x",
      "the S3 error text is shown as sent")
    #expect(S3ConnectionsSection.resultLine(.ok(count: 3), locale: locale).contains("3"))
    let capped = S3ConnectionsModel.testLimit
    #expect(
      S3ConnectionsSection.resultLine(.ok(count: capped), locale: locale)
        != S3ConnectionsSection.resultLine(.ok(count: capped - 1), locale: locale)
        .replacingOccurrences(of: "\(capped - 1)", with: "\(capped)"),
      "a full page says « at least »")
    for result: S3ConnectionsModel.TestResult in [.running, .secretMissing, .noConnection] {
      #expect(!S3ConnectionsSection.resultLine(result, locale: locale).isEmpty)
    }
  }
}
