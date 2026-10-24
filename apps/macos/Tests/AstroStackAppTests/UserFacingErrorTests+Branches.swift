import AstroStackApp
import ProcessKit
import Testing

extension UserFacingErrorTests {
  /// Why a branch refuses a process (card 0118): what to do instead, the process named.
  nonisolated static let branchCases: [Case] = [
    Case(
      error: StudioError.notBranchable(processID: "geometry", reason: .movesPixels),
      names: "geometry",
      english: "“geometry” moves the pixels: crop, turn or flip in the main history."),
    Case(
      error: StudioError.notBranchable(processID: "stretch", reason: .notPerLayer),
      names: "stretch", english: "“stretch” works on the whole image: apply it in the main history."
    ),
    Case(
      error: StudioError.notBranchable(processID: "colour-balance", reason: .needsColour),
      names: "colour-balance",
      english: "“colour-balance” needs a colour layer: a line layer has a single plane."),
  ]

  @Test("every branch refusal has an English and a French sentence", arguments: branchCases)
  func testEveryBranchRefusalHasASentence(_ row: Case) {
    testEverySirilAndImportErrorHasASentence(row)
  }
}
