import Foundation
import StackKit
import Testing

@Suite("OmittedFalse: Go's omitempty booleans")
struct OmittedFalseTests {
  struct Flagged: Decodable {
    @OmittedFalse var flag: Bool
  }

  @Test(
    "absent and null decode as false; a present value decodes as is",
    arguments: [
      ("{}", false), (#"{"flag": null}"#, false), (#"{"flag": true}"#, true),
      (#"{"flag": false}"#, false),
    ])
  func testOmittedFalse_decode(json: String, expected: Bool) throws {
    let decoded = try JSONDecoder().decode(Flagged.self, from: Data(json.utf8))
    #expect(decoded.flag == expected)
  }

  @Test("a non-boolean value is an error, not false")
  func testOmittedFalse_decode_rejectsWrongType() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Flagged.self, from: Data(#"{"flag": "yes"}"#.utf8))
    }
  }
}
