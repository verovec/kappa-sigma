import ProcessKit
import StackKit
import Testing

/// A profile's preprocessing knobs are 0070's (card 0060): each id is a `KnobSchema` knob that
/// accepts the profile's value — a profile never carries a knob the preprocessing cannot apply.
@Suite("Profiles — preprocessing knobs are KnobSchema's")
struct ProfileKnobTests {
  @Test("every builtin knob exists and accepts its value; the mode is a preset")
  func testKnobsValidate() throws {
    for profile in try ProfileLibrary.builtins(registry: ProcessRegistry.standard()) {
      #expect(PreprocessRequest.Mode(rawValue: profile.preprocessing.mode) != nil, "\(profile.id)")
      for (id, value) in profile.preprocessing.knobs {
        let knob = try #require(KnobSchema.knob(id), "\(profile.id): knob \(id)")
        let converted: KnobValue? =
          switch value {
          case .number(let number): .number(number)
          case .flag(let flag): .flag(flag)
          case .choice(let option): .choice(option)
          case .points: nil
          }
        #expect(converted.map(knob.accepts) == true, "\(profile.id): \(id) = \(value)")
      }
    }
  }
}
