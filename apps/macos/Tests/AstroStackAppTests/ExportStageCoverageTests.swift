import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// What the Export stage says and offers beyond the card's three tests (card 0091): every error
/// sentence in fr and en, the form's titles, StarNet's re-check, separation from the Studio.
@MainActor
@Suite("Export stage — sentences, titles, re-check, separation from the Studio")
struct ExportStageCoverageTests {
  nonisolated static let errors: [UserFacingError] = [
    .starnet(.missing(path: "/usr/local/bin/starnet2")),
    .starnet(.cannotRun(path: "/usr/local/bin/starnet2", reason: "needs Rosetta")),
    .starnet(.probeTimedOut(path: "/usr/local/bin/starnet2")),
    .starnet(.failed(exitCode: 3, log: "Working: 50.0%\nmodel not found\n\n")),
    .starnet(.noOutput(path: "/tmp/out.tif")),
    .export(.readOnlyTarget("/r is read-only")), .export(.sizeMismatch),
    .export(.rowOrderMismatch), .export(.cropTooLarge(0.5)), .export(.invalidCrop(-1)),
    .export(.invalidTemplate("a/{name}")), .export(.needsStarless([.stars25])),
    .exportReadOnlyFolder(path: "/r"), .exportNothingChosen,
    .exportWouldOverwrite(path: "/x/final.png"), .history(.movedDuring("starnet")),
  ]

  @Test("every export and StarNet error is one sentence in fr and en", arguments: errors)
  func testSentences(_ error: UserFacingError) {
    for language in ["fr", "en"] {
      var message = error.message
      message.locale = Locale(identifier: language)
      let text = String(localized: message)
      #expect(!text.isEmpty && !text.contains("%"), "\(language): \(text)")
    }
  }

  @Test("a StarNet failure shows its last line, a crop in the user's notation")
  func testFailureWording() {
    var failed = UserFacingError.starnet(
      .failed(exitCode: 3, log: "Working: 50%\nmodel not found\n")
    )
    .message
    failed.locale = Locale(identifier: "en")
    #expect(String(localized: failed) == "StarNet stopped with code 3: model not found")
    #expect(UserFacingError(StarNetError.noOutput(path: "/o")) == .starnet(.noOutput(path: "/o")))
    #expect(UserFacingError(DeliverableExport.ExportError.sizeMismatch) == .export(.sizeMismatch))
  }

  @Test("every file, format and mirror has a title in fr and en")
  func testFormTitles() {
    let titles =
      ExportSettings.Deliverable.allCases.map(ExportForm.title)
      + ExportSettings.Format.allCases.map(ExportForm.title)
      + ExportSettings.Orientation.allCases.map(ExportForm.title)
    for var title in titles {
      title.locale = Locale(identifier: "fr")
      #expect(!String(localized: title).isEmpty)
    }
    #expect(Set(titles.map { String(localized: $0) }).count == titles.count)
  }

  @Test(
    "the install card's re-check finds a StarNet that runs, refuses a missing one",
    .scratchDirectory)
  func testRecheck() async throws {
    let binary = try FakeStarNet.install(in: try ScratchDirectory.url)
    let found = await StarSeparation.check(HostTools { _ in .found(path: binary, version: nil) })()
    #expect(found == .found(URL(fileURLWithPath: binary)))
    let missing = await StarSeparation.check(HostTools { _ in .missing(path: "/none") })()
    #expect(missing == .missing)
  }

  @Test(
    "Separate Stars from the Studio leads to the Export stage and records the step",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testSeparateFromStudio() async throws {
    let binary = try FakeStarNet.install(in: try ScratchDirectory.url)
    let tools = HostTools { _ in .found(path: binary, version: nil) }
    let opened = try await ExportStagePaneTests.open(tools: tools)
    defer { try? opened.project.close() }
    let window = opened.window
    window.select(.studio)
    let studio = try #require(window.workspace?.studio)
    let studioPane = AccessibilityAuditTests.entries(
      ProjectWindowView(model: window, projects: .empty))
    #expect(studioPane.contains { $0.id == "fr.astrostack.stage.export.separate" })

    window.separateStarsFromStudio()
    #expect(window.selection == .export)
    await ExportStageModelTests.wait { studio.steps.last?.processID == StarSeparation.id }
    await ExportStageModelTests.wait { window.exportStage?.isSeparating == false }

    #expect(window.exportStage?.hasStarless == true)
    #expect(
      window.workspace?.catalogue.flatMap(\.entries).first { $0.id == "star-recomposition" }?
        .unavailable == nil)
    let view = AccessibilityAuditTests.entries(
      ExportStageView(model: try #require(window.exportStage)))
    #expect(view.contains { $0.id == "fr.astrostack.stage.export.separate" })
  }

  @Test(
    "a refused export shows its sentence; steps after the separation are counted",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testFailureAndLateSteps() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try ExportStageModelTests.separated(opened)
    try studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    let model = try ExportStageModelTests.model(
      opened, studio: studio, services: try ExportStageModelTests.services())
    model.settings.choose(.png16, false)
    await model.export()
    #expect(model.failure == .exportNothingChosen && model.stepsAfterStarless == 1)
    let entries = AccessibilityAuditTests.entries(ExportStageView(model: model))
    #expect(AccessibilityAudit.problems(entries) == [])
    _ = AccessibilityAuditTests.entries(StarSeparationSection(model: model))
  }

  @Test(
    "Reveal in Finder shows the files; a failed write is said; a bundle's starless is used",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testRevealFailureAndBundleStarless() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    var bundle = StudioModelTests.bundle()
    let rgb = try #require(bundle.layers["RGB"])
    bundle.layers["starless"] = AstroImage(
      width: rgb.width, height: rgb.height, planes: rgb.planes.map { $0.map { $0 / 2 } },
      metadata: rgb.metadata)
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: bundle)
    let revealed = Recorded<[URL]>()
    var services = try ExportStageModelTests.services()
    services.reveal = { revealed.append($0) }
    let model = try ExportStageModelTests.model(opened, studio: studio, services: services)
    #expect(model.hasStarless)

    model.settings.nameTemplate = "a/{name}"
    await model.export()
    #expect(model.failure == .export(.invalidTemplate("a/{name}")))

    model.settings.nameTemplate = "{name}"
    await model.export()
    let record = try #require(model.exports.first)
    #expect(record.files.count == ExportSettings.Deliverable.allCases.count)
    model.reveal(record)
    #expect(revealed.all.first?.map(\.lastPathComponent) == record.files)
  }
}

extension ExportStageCoverageTests {
  @Test("a window planning without master services has none, and previewing a master is nothing")
  func testWindowWithoutMasterServices() {
    let window = ProjectWindowModel(store: { nil }, planning: { _ in ImportPlanningStub.empty })
    #expect(window.masters == nil)
    window.previewMaster("/library/bias.fits")
    #expect(window.masters == nil && window.error == nil)
  }
}
