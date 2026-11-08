import AstroStackApp
import Foundation
import TestSupport
import Testing

extension ExportTargetsTests {
  @Test(
    "a key that could not check existing objects is said under the targets (card 0185)",
    .scratchDirectory, arguments: ["en", "fr"])
  func testUncheckedKeyLine(_ language: String) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let checked = try ExportStageModelTests.s3Model(
      opened, fake: ExportS3Fake(head: 404), local: false, s3: true)
    let writeOnly = try ExportStageModelTests.s3Model(
      opened, fake: ExportS3Fake(head: 403), local: false, s3: true)
    await checked.export()
    await writeOnly.export()

    #expect(!checked.remoteUnchecked && writeOnly.remoteUnchecked)
    let plain = Self.host(ExportTargetsForm(model: checked), language).height
    let said = Self.host(ExportTargetsForm(model: writeOnly), language).height
    #expect(said > plain, "one more line: \(said) vs \(plain)")
  }
}
