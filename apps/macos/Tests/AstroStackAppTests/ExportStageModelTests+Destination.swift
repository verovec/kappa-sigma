import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

/// Where the Export stage writes (card 0151): the remembered base + the template, never the
/// project package; « Choose… » for one export, « Remember as default » to keep it.
extension ExportStageModelTests {
  static func suite() throws -> (UserDefaults, String) {
    let name = "fr.astrostack.tests.exportstage.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
  }

  @Test(
    "testFolderIsBasePlusTemplate: no exports folder under the package, ever", .scratchDirectory)
  func testFolderIsBasePlusTemplate() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let model = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: try Self.services())
    #expect(model.base == (try Self.defaultBase()))
    #expect(model.template == ExportPathTemplate.standard)
    let folder = try #require(model.folder)
    #expect(folder.path == (try Self.defaultBase()).path + "/M31/run1/2026-10-22-120000")
    #expect(!folder.path.hasPrefix(opened.package.url.path))
    #expect(!folder.pathComponents.contains("exports"))

    await model.export()

    #expect(model.failure == nil)
    #expect(model.written.allSatisfy { $0.deletingLastPathComponent() == folder })
    #expect(!FileManager.default.fileExists(atPath: opened.package.url.path + "/exports"))
  }

  @Test("testChooseOnceDoesNotPersist: « Choose… » serves this export only", .scratchDirectory)
  func testChooseOnceDoesNotPersist() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let services = try Self.services(suite: name)
    let model = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: services)
    let chosen = try ScratchDirectory.url.appendingPathComponent("NAS/Astro")
    try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
    model.base = chosen
    model.template = "{object}"

    await model.export()

    #expect(model.failure == nil)
    #expect(
      model.written.first?.deletingLastPathComponent() == chosen.appendingPathComponent("M31"))
    #expect(services.destination.chosenBase == nil)
    #expect(services.destination.template.text == ExportPathTemplate.standard)
    let next = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: services)
    #expect(next.base == (try Self.defaultBase()) && next.template == ExportPathTemplate.standard)
  }

  @Test("testRememberPersists: the base and template become the default", .scratchDirectory)
  func testRememberPersists() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let services = try Self.services(suite: name)
    let model = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: services)
    let chosen = try ScratchDirectory.url.appendingPathComponent("NAS/Astro")
    try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
    model.base = chosen
    model.template = "{object}/{date}"
    model.remember = true

    await model.export()

    #expect(model.failure == nil)
    #expect(services.destination.chosenBase?.path == chosen.standardizedFileURL.path)
    #expect(services.destination.template.text == "{object}/{date}")
    let next = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: services)
    #expect(next.base.path == chosen.standardizedFileURL.path && next.template == "{object}/{date}")
  }

  @Test(
    "a folder the app writes under is refused before any file, remembered or not",
    .scratchDirectory, arguments: [true, false])
  func testRememberRefusedWritesNothing(remember: Bool) async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let services = try Self.services(suite: name)
    let model = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: services)
    let projects = try ScratchDirectory.url.appendingPathComponent("home/AstroStack/Projects")
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    model.base = projects
    model.template = ""
    model.remember = remember

    await model.export()

    #expect(model.failure == .exportBaseRefused(path: projects.path, .appOwned))
    #expect(model.written.isEmpty && services.destination.chosenBase == nil)
  }

  @Test("a chosen base that is gone is reported, never made again", .scratchDirectory)
  func testMissingBaseReported() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let model = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: try Self.services())
    let gone = try ScratchDirectory.url.appendingPathComponent("Volumes/Unplugged")
    model.base = gone

    await model.export()

    #expect(model.failure == .exportFolderMissing(path: gone.path))
    #expect(String(localized: try #require(model.failure).message).contains(gone.path))
    #expect(!FileManager.default.fileExists(atPath: gone.path) && model.written.isEmpty)
  }

  @Test(
    "a template that cannot name a folder shows why; nothing can be exported", .scratchDirectory)
  func testRefusedTemplate() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let model = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: try Self.services())
    model.template = "{target}"
    let refusal = ExportPathTemplate.Refusal.unknownToken(
      "target", valid: ExportPathTemplate.tokens)
    #expect(model.folder == nil && model.folderRefusal == refusal && !model.canExport)

    await model.export()

    #expect(model.failure == .exportTemplate(refusal))
    let message = String(localized: try #require(model.failure).message)
    #expect(message.contains("{target}") && message.contains(ExportPathTemplate.listed))
    #expect(model.written.isEmpty)
  }

  @Test("an export never replaces files: the same folder twice is refused", .scratchDirectory)
  func testRefusesToOverwrite() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let model = try Self.model(opened, studio: studio, services: try Self.services())
    let used = model.folder
    await model.export()
    let first = try #require(model.written.first)
    // The default moves on (a second later at least, even on a fixed clock).
    #expect(model.folder != used)

    // A template without the time names the same folder twice.
    model.template = "{object}/{date}"
    await model.export()
    #expect(
      model.failure == nil && model.written.first?.deletingLastPathComponent() == model.folder)
    let second = try #require(model.written.first)
    await model.export()

    #expect(model.failure == .exportWouldOverwrite(path: second.path))
    #expect(try opened.package.store.exports(stackID: opened.stackID).count == 2)
    #expect(first != second)
  }

  @Test("an export into the folder of an earlier one is refused", .scratchDirectory)
  func testRefusesToOverwriteAChosenBase() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let model = try Self.model(opened, studio: studio, services: try Self.services())
    let chosen = try ScratchDirectory.url.appendingPathComponent("Deliverables")
    try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
    model.base = chosen
    model.template = ""
    await model.export()
    let first = try #require(model.written.first)
    #expect(first.deletingLastPathComponent().standardizedFileURL == chosen.standardizedFileURL)

    await model.export()

    #expect(model.failure == .exportWouldOverwrite(path: first.path))
    #expect(try opened.package.store.exports(stackID: opened.stackID).count == 1)
  }

  @Test("the {project} token follows the package where it is now", .scratchDirectory)
  func testDefaultFolderFollowsThePackage() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    var place = opened.package.url
    let stack = try #require(try opened.package.store.stack(id: opened.stackID))
    let model = ExportStageModel(
      studio: try StudioModelTests.model(opened), stack: stack, store: opened.package.store,
      packageFolder: { place }, services: try Self.services())
    model.template = "{project}"
    place = try ScratchDirectory.url.appendingPathComponent("Moved.astrostack")
    #expect(model.folder?.path == (try Self.defaultBase()).path + "/Moved")
    let chosen = try ScratchDirectory.url.appendingPathComponent("Deliverables")
    model.base = chosen
    #expect(model.folder?.path == chosen.path + "/Moved")
  }

  @Test("« Remember » on the default base stores no base, only the template", .scratchDirectory)
  func testRememberDefaultStoresNoBase() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let services = try Self.services(suite: name)
    let model = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: services)
    model.template = "{object}/{time}"
    model.remember = true

    await model.export()

    #expect(model.failure == nil)
    #expect(defaults.string(forKey: ExportDestinationSetting.baseKey) == nil)
    #expect(services.destination.template.text == "{object}/{time}")
  }

  @Test("a template that walks into the projects is refused like a base there", .scratchDirectory)
  func testTemplateIntoProjectsRefused() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let model = try Self.model(
      opened, studio: try StudioModelTests.model(opened), services: try Self.services())
    let home = try ScratchDirectory.url.appendingPathComponent("home")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    model.base = home
    model.template = "AstroStack/Projects/{object}"

    await model.export()

    let folder = home.appendingPathComponent("AstroStack/Projects/M31", isDirectory: true)
    #expect(model.failure == .exportBaseRefused(path: folder.path, .appOwned))
    #expect(model.written.isEmpty && !FileManager.default.fileExists(atPath: folder.path))
  }
}
