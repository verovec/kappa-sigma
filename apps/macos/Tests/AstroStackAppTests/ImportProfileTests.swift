import AstroStackApp
import Foundation
import ProcessKit
import ProjectKit
import StackKit
import TestSupport
import Testing

/// The Import sheet proposes a profile with its reasons (card 0060); the user keeps it, picks
/// another or none, and Add records the choice in the project — nothing applied by itself (R2).
@MainActor
@Suite("Import — profile proposal, choice, recorded on Add")
struct ImportProfileTests {
  /// A planner answering an M 31 broadband + dual-band OSC inventory.
  static let m31: ImportViewModel.Planning = { request in
    ImportPlan(
      inventory: ProfileInputsTests.inventory([
        ProfileInputsTests.LightSet("M 31", Filter.color, true, .broadband),
        ProfileInputsTests.LightSet("M 31", Filter.color, true, .dualband),
      ]), library: [], request: request)
  }

  static func model() async -> ImportViewModel {
    let model = ImportViewModel(planning: Self.m31)
    model.choose(folder: URL(fileURLWithPath: "/c/M31"))
    await model.settled()
    return model
  }

  @Test("the plan's inventory proposes the galaxy profile, selected until the user picks")
  func testProposalAndChoice() async throws {
    let model = await Self.model()
    let proposal = try #require(model.proposal)
    #expect(proposal.proposed?.id == "galaxy-osc-broadband-dualband")
    #expect(proposal.reasons.contains(.onlyMatch))
    #expect(model.selectedProfile?.id == "galaxy-osc-broadband-dualband")
    model.chooseProfile(.profile("cluster-osc-broadband"))
    #expect(model.selectedProfile?.id == "cluster-osc-broadband")
    model.chooseProfile(.none)
    #expect(model.selectedProfile == nil, "no profile is a choice too")
  }

  @Test("Add records the kept profile with each imported source", .scratchDirectory)
  func testAddRecordsProfile() async throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let window = ProjectWindowModel(store: { project.store }, planning: { _ in Self.m31 })
    window.startImport()
    let importing = try #require(window.importing)
    importing.choose(folder: URL(fileURLWithPath: "/c/M31"))
    await importing.settled()
    window.add(importing.request)
    #expect(try project.store.sources().map(\.profileID) == ["galaxy-osc-broadband-dualband"])

    // A second night with no profile kept leaves the first night's choice alone.
    window.startImport()
    let second = try #require(window.importing)
    second.choose(folder: URL(fileURLWithPath: "/c/M31-night2"))
    await second.settled()
    second.chooseProfile(.none)
    window.add(second.request)
    #expect(try project.store.sources().map(\.profileID) == ["galaxy-osc-broadband-dualband", nil])
  }

  @Test("a plan that is not the request's records nothing", .scratchDirectory)
  func testStalePlanNotRecorded() async throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let window = ProjectWindowModel(store: { project.store }, planning: { _ in Self.m31 })
    window.startImport()
    let importing = try #require(window.importing)
    // Add before any scan: no plan, no proposal the user saw.
    window.add(ImportRequest(paths: ["/c/IC1848"]))
    #expect(try project.store.sources().map(\.profileID) == [nil])
    #expect(importing.planIsCurrent == false)
  }

  @Test("an explicit pick is recorded whatever the plan; another request's sources get nothing")
  func testWhatAddRecords() async throws {
    let model = ImportViewModel(planning: Self.m31)
    model.choose(folder: URL(fileURLWithPath: "/c/M31"))
    // No scan finished: the proposal is not recorded, an explicit pick is.
    #expect(model.profileToRecord(for: model.request) == nil)
    model.chooseProfile(.profile("cluster-osc-broadband"))
    #expect(model.profileToRecord(for: model.request) == KeptProfile(id: "cluster-osc-broadband"))
    model.chooseProfile(.none)
    #expect(model.profileToRecord(for: model.request) == KeptProfile(id: nil))
    #expect(model.profileToRecord(for: ImportRequest(paths: ["/c/IC1848"])) == nil)
    await model.settled()
    model.chooseProfile(.proposed)
    #expect(
      model.profileToRecord(for: model.request) == KeptProfile(id: "galaxy-osc-broadband-dualband"))
  }

  @Test("nothing proposed records nothing: a source keeps the profile it had")
  func testNothingProposedRecordsNothing() async throws {
    let model = ImportViewModel(planning: { request in
      ImportPlan(
        inventory: ProfileInputsTests.inventory([
          ProfileInputsTests.LightSet("Sh2-129", Filter.color, true, .unknown)
        ]), library: [], request: request)
    })
    model.choose(folder: URL(fileURLWithPath: "/c/Sh2-129"))
    await model.settled()
    #expect(model.proposal?.proposed == nil)
    #expect(model.profileToRecord(for: model.request) == nil)
    #expect(ImportProfileView.tag(for: model) == ImportProfileView.undecided, "never shown as none")
    model.chooseProfile(ImportProfileView.choice(for: ""))
    #expect(
      model.profileToRecord(for: model.request) == KeptProfile(id: nil),
      "« No profile » records none")
  }

  @Test("a new folder resets the profile choice to the proposal")
  func testFolderResetsChoice() async throws {
    let model = await Self.model()
    model.chooseProfile(.none)
    model.choose(folder: URL(fileURLWithPath: "/c/M31-other"))
    await model.settled()
    #expect(model.selectedProfile?.id == "galaxy-osc-broadband-dualband")
  }

  @Test("the import offers the project's user copies over the shipped profiles", .scratchDirectory)
  func testUserCopiesOffered() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    var copy = try #require(
      ImportViewModel.shippedProfiles.first { $0.id == "emission-osc-dualband" })
    try copy.set("lumaDesat", to: .number(0.5), inStep: 3)
    try project.store.saveUserProfile(id: copy.id, json: copy.json())
    try project.store.saveUserProfile(id: "broken", json: Data("{}".utf8))
    let loaded = ImportViewModel.profiles(store: project.store)
    #expect(loaded.profiles.count == 5, "the copy shadows its builtin; the broken copy is left out")
    #expect(loaded.profiles.first { $0.id == copy.id }?.isUserCopy == true)
    #expect(loaded.rejected.keys.sorted() == ["broken"], "and the broken one is listed")
  }

  @Test("each reason and each profile reads in French and English")
  func testWords() throws {
    let french = Locale(identifier: "fr")
    for reason: ProfileProposal.Reason in [
      .camera(.osc), .camera(.mono), .filters(.broadbandDualband), .object("M 31"), .onlyMatch,
    ] {
      var english = ImportProfileView.words(for: reason, locale: Locale(identifier: "en"))
      english.locale = Locale(identifier: "en")
      var resource = ImportProfileView.words(for: reason, locale: french)
      resource.locale = french
      #expect(String(localized: resource) != String(localized: english), "\(reason)")
    }
    for filters in Profile.Filters.allCases {
      var resource = ImportProfileView.words(for: .filters(filters), locale: french)
      resource.locale = french
      #expect(!String(localized: resource).isEmpty)
    }
  }
}
