import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import StackKit
import Synchronization
import Testing

/// Card 0130: the sidebar's Objects — the catalogue loaded once, the project's object matched by
/// the one name key, a type-ahead search, a missing Siril greying the section.
@MainActor
@Suite("Objects in the sidebar — default object, search, Siril missing")
struct ObjectSearchModelTests {
  nonisolated static let catalogue = SkyCatalogue(objects: [
    SkyObject(
      name: "M31", raDeg: 10.684793, decDeg: 41.269065, source: .messier, magnitude: 3.4,
      aliases: ["NGC224"], commonNames: ["Andromeda Galaxy"]),
    SkyObject(name: "Sh2-132", raDeg: 334.698615, decDeg: 56.134831, source: .sh2),
    SkyObject(name: "Sh2-131", raDeg: 315.4, decDeg: 57.5, source: .sh2),
  ])

  static func model() -> ObjectSearchModel {
    ObjectSearchModel(load: { Self.catalogue }, locate: { _ in .missing(path: "") })
  }

  @Test(
    "the project's object pre-selects its entry through the name key; unknown selects nothing",
    arguments: [
      ("SH2-132", "Sh2-132"), ("M 31", "M31"), ("NGC 224", "M31"), ("Mystery", nil), ("", nil),
    ])
  func testObjectSearchDefaultsToProjectObject(_ project: String, _ expected: String?) async {
    let objects = Self.model()
    await objects.load(projectObject: project)
    #expect(objects.selected?.name == expected)
    #expect(objects.offered?.name == expected, "the plate solve offers the selection")
    #expect(objects.query.isEmpty, "nothing typed for the user")
  }

  @Test("the search is the catalogue's, at most 20; a choice replaces the offer")
  func testSearchAndChoose() async throws {
    let objects = Self.model()
    await objects.load(projectObject: "M31")
    objects.query = "sh2 13"
    // Same rank, list and (unknown) magnitude: merge order.
    #expect(objects.results.map(\.name) == ["Sh2-132", "Sh2-131"])
    objects.choose(try #require(objects.results.first))
    #expect(objects.selected?.name == "Sh2-132" && objects.cardShown)
    objects.closeCard()
    #expect(!objects.cardShown && objects.offered?.name == "Sh2-132", "closing keeps the choice")
  }

  @Test("no Siril: the section is unavailable with the reason, nothing searched or offered")
  func testObjectSearchSirilMissingGreys() async {
    let objects = ObjectSearchModel(
      load: {
        throw SkyCatalogueError.sirilMissing(
          path: "/Applications/Siril.app/Contents/MacOS/siril-cli")
      }, locate: { _ in .missing(path: "") })
    await objects.load(projectObject: "M31")
    #expect(
      objects.unavailable == .sirilMissing(path: "/Applications/Siril.app/Contents/MacOS/siril-cli")
    )
    objects.query = "m31"
    #expect(objects.results.isEmpty && objects.offered == nil)
    #expect(objects.sirilCard != nil, "its install card, re-checked through the host-tool client")
  }

  @Test("loaded once: a second load only re-matches the project's object")
  func testLoadedOnce() async {
    let loads = LoadCounter()
    let objects = ObjectSearchModel(
      load: {
        loads.increment()
        return Self.catalogue
      }, locate: { _ in .missing(path: "") })
    await objects.load(projectObject: "M31")
    await objects.load(projectObject: "Sh2-132")
    #expect(loads.count == 1)
    #expect(objects.selected?.name == "Sh2-132")
  }

  /// Counts the loader's calls across the actor hop.
  final class LoadCounter: Sendable {
    private let calls = Mutex(0)
    var count: Int { calls.withLock { $0 } }
    func increment() { calls.withLock { $0 += 1 } }
  }

  @Test(
    "the project's object is its stack's OBJECT; a stack of unnamed lights names none",
    .scratchDirectory, arguments: [("SH2-132", "SH2-132"), ("", nil)])
  func testProjectObjectName(_ recorded: String, _ expected: String?) throws {
    let project = try ProjectPackage.create(
      at: try ScratchDirectory.url.appendingPathComponent("SH2-132.astrostack"))
    defer { try? project.close() }
    _ = try project.store.addStack(
      bundlePath: "stacks/run1", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB"],
      object: recorded)
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      services: { _ in ImportServices(planning: ImportPlanningStub.empty) }, objects: Self.model())
    #expect(window.projectObjectName == expected, "the project's own name is never a guess")
  }

  @Test("the Objects help card passes the stage-card gate in fr and en")
  func testObjectsHelpCard() {
    #expect(AppGlossary.help.coverageProblems(stages: [ObjectsHelp.cardID]) == [])
    #expect(ObjectsHelp.help(locale: Locale(identifier: "fr")) != nil)
  }

  @Test(
    "an OpenNGC type in words, an unknown code as given",
    arguments: [("G", "en", "Galaxy"), ("HII", "fr", "Région H II"), ("Dup", "en", "Dup")])
  func testTypeWords(_ code: String, _ language: String, _ words: String) {
    #expect(SkyObjectWords.type(code, locale: Locale(identifier: language)) == words)
  }

  @Test("size and magnitude through the locale's numbers; unknown ones left out")
  func testSizeAndMagnitude() {
    var m31 = SkyObject(
      name: "M31", raDeg: 10.68, decDeg: 41.27, source: .messier, magnitude: 3.4,
      majorAxisArcmin: 177.83)
    m31.minorAxisArcmin = 69.66
    let french = Locale(identifier: "fr")
    #expect(SkyObjectWords.size(m31, locale: french) == "177,8′ × 69,7′")
    #expect(SkyObjectWords.magnitude(m31, locale: french) == "3,4")
    let sh2 = SkyObject(name: "Sh2-132", raDeg: 0, decDeg: 0, source: .sh2)
    #expect(
      SkyObjectWords.size(sh2, locale: french) == nil
        && SkyObjectWords.magnitude(sh2, locale: french) == nil)
  }

  @Test("the offer callback fires when the offered object changes, not when it stays")
  func testOfferCallback() async throws {
    let objects = Self.model()
    var told = 0
    objects.onOffer = { told += 1 }
    await objects.load(projectObject: "M31")
    #expect(told == 1)
    await objects.load(projectObject: "M 31")
    #expect(told == 1, "the same object: nothing to rebuild")
    objects.choose(try #require(Self.catalogue.object(named: "Sh2-132")))
    #expect(told == 2)
  }

  @Test("a load cancelled meanwhile writes no selection")
  func testCancelledLoadWritesNothing() async {
    let objects = Self.model()
    let task = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      await objects.load(projectObject: "M31")
    }
    await task.value
    #expect(objects.selected == nil)
    await objects.load(projectObject: "Sh2-132")
    #expect(objects.selected?.name == "Sh2-132", "the catalogue read once is kept")
  }
}
