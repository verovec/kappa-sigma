import Foundation
import StackKit
import Testing

/// What a failed run tells the user: each error names what it is about and what to do.
@Suite("PreprocessError — messages a user can act on")
struct PreprocessErrorTests {
  @Test(
    "every case names its subject",
    arguments: [
      (PreprocessError.belowStackMinimum(survivors: 1, registered: 5), "1 of 5 registered frames"),
      (.mixedDimensions(["R 64×64", "G 32×32"]), "R 64×64, G 32×32"),
      (.targetBusy("/p/out"), "/p/out"),
      (.noChannels(["L: no stars"]), "L: no stars"),
      (.mixedColorModel, "mono and colour"),
    ])
  func testDescriptions(error: PreprocessError, fragment: String) {
    #expect(error.localizedDescription.contains(fragment))
  }
}
