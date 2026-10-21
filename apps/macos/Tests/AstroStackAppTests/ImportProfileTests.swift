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

  @Test("Add records the selected profile in the project", .scratchDirectory)
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
    #expect(
      try project.store.setting(ProfileChoice.settingKey)
        == "galaxy-osc-broadband-dualband")
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
