internal import Foundation
package import ProjectKit
package import StackKit

/// What a stack's `params_json` holds: the import it planned (legacy `RunRequest` keys), the
/// preset it ran and the knobs the user moved from it (card 0070) — enough to run it again.
///
/// One flat JSON object: the request's own keys, then `mode` and `knobs` (left out when no knob
/// moved). A record written before 0070 reads as the deepsky preset, untouched.
package struct StackRecord: Equatable, Sendable {
  /// The import the run planned, with its overrides.
  package var request: ImportRequest
  /// The preset the run started from.
  package var mode: PreprocessRequest.Mode
  /// The knobs moved from that preset.
  package var knobs: KnobPatch

  /// A record of `request` run with the preset of `mode` and `knobs`.
  package init(
    request: ImportRequest, mode: PreprocessRequest.Mode = .deepsky, knobs: KnobPatch = KnobPatch()
  ) {
    self.request = request
    self.mode = mode
    self.knobs = knobs
  }
}

extension StackRecord {
  /// The record `stack` holds in its `params_json`.
  package init(stack: ProjectStack) throws {
    self = try JSONDecoder().decode(Self.self, from: Data(stack.paramsJSON.utf8))
  }
}

extension StackRecord: Codable {
  private enum Key: String, CodingKey {
    case mode, knobs
  }

  package init(from decoder: any Decoder) throws {
    request = try ImportRequest(from: decoder)
    let record = try decoder.container(keyedBy: Key.self)
    mode = try record.decodeIfPresent(PreprocessRequest.Mode.self, forKey: .mode) ?? .deepsky
    knobs = try record.decodeIfPresent(KnobPatch.self, forKey: .knobs) ?? KnobPatch()
  }

  package func encode(to encoder: any Encoder) throws {
    try request.encode(to: encoder)
    var record = encoder.container(keyedBy: Key.self)
    try record.encode(mode, forKey: .mode)
    if !knobs.values.isEmpty { try record.encode(knobs, forKey: .knobs) }
  }
}
