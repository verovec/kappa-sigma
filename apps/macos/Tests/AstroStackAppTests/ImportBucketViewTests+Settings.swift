import AstroStackApp
import Foundation
import Testing

extension ImportBucketViewTests {
  /// Card 0177: « add one in Settings › S3 connections » was text only, and Settings was found
  /// through the menu bar alone.
  @Test(
    "testOpensS3Connections: « S3 connections… » is offered with and without connections",
    arguments: [0, 1])
  func testOpensS3Connections(connections: Int) {
    var opened: [SettingsTab?] = []
    let model = Self.model(connections: Array([Self.connection].prefix(connections)))
    let view = ImportBucketView(model: model, onScan: { _ in }, openSettings: { opened.append($0) })

    let entries = AccessibilityAuditTests.entries(view)
    view.settingsButton.press()

    #expect(entries.contains { $0.id == "fr.astrostack.settings.open.s3" }, "\(entries.map(\.id))")
    #expect(opened == [.s3])
  }
}
