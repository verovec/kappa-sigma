import StackKit
import Testing

/// A run that planned a colour composite but ends on one grey master warns (card 0173); a run that
/// never had the channels for one keeps its note only.
extension ChannelCombinerTests {
  @Test(
    "a colour run that lost a channel says so; a run that never had one stays silent",
    arguments: [
      (
        ["L", "R", "G", "B", "Ha"], ["L": "l", "G": "g", "B": "b", "Ha": "h"],
        "no colour composite: R missing — combined = L alone, in grey"
      ),
      (
        ["L", "R", "G", "B"], ["L": "l", "R": "r"],
        "no colour composite: G, B missing — combined = L alone, in grey"
      ),
      (
        ["RGB", "Ha"], ["Ha": "h"],
        "no colour composite: RGB missing — combined = Ha alone, in grey"
      ),
      // No L: the mono fallback is Hα, and it is what the warning names.
      (
        ["R", "G", "B", "Ha"], ["G": "g", "B": "b", "Ha": "h"],
        "no colour composite: R missing — combined = Ha alone, in grey"
      ),
      // A split capture's lanes are its base filter's: the broadband RGB lane was the plan.
      (
        ["RGB", "RGB-dualband"], ["Ha": "h"],
        "no colour composite: RGB missing — combined = Ha alone, in grey"
      ),
      (["L", "R", "G", "B"], ["L": "l", "R": "r", "G": "g", "B": "b"], nil),
      // A lost L still makes RGB: a colour composite, no warning.
      (["L", "R", "G", "B"], ["R": "r", "G": "g", "B": "b"], nil),
      (["L"], ["L": "l"], nil),
      (["Ha", "OIII"], ["Ha": "h", "OIII": "o"], nil),
      // R + G + Hα never spelled a composite: mono by design, not a loss.
      (["R", "G", "Ha"], ["R": "r", "G": "g", "Ha": "h"], nil),
      (["L", "R", "G", "B"], [:], nil),
    ] as [([String], [String: String], String?)])
  func testFallbackWarning(planned: [String], channels: [String: String], expected: String?) {
    #expect(ChannelCombiner.fallbackWarning(planned: planned, channels: channels) == expected)
  }
}
