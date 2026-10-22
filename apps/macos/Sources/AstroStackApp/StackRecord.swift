internal import Foundation
package import ProjectKit
package import StackKit

/// What a stack's `params_json` holds: the import it planned (legacy `RunRequest` keys), the
/// preset it ran and the knobs the user moved from it (card 0070) — enough to run it again.
///
/// One flat JSON object: the request's own keys, then `mode`, `knobs` (left out when no knob
/// moved) and `scope` (left out when the run took every light). A record written before 0070
/// reads as the deepsky preset, untouched; before 0095, unscoped.
package struct StackRecord: Equatable, Sendable {
  /// The import the run planned, with its overrides.
  package var request: ImportRequest
  /// The preset the run started from.
  package var mode: PreprocessRequest.Mode
  /// The knobs moved from that preset.
  package var knobs: KnobPatch
  /// The series the run stacked (card 0095): one object's light sets; `nil` = every light of
  /// the request's nights (a record written before 0095, or a project with one object and no scan).
  package var scope: RunScope?
  /// A recorded preset this build does not know: read as deepsky, and shown.
  package var unknownMode: String?
  /// The frame review's decisions per lane (card 0069, `frame_review`): one entry per lane the run
  /// paused on, empty lists when the hand changed nothing; nil when the run never paused.
  package var frameReview: [String: FrameDecision]?
  /// The registration reference pinned per lane (card 0096, `reference_pins`); nil when the run
  /// never paused there or every election was kept.
  package var referencePins: [String: Int]?

  /// A record of `request` run with the preset of `mode` and `knobs`.
  package init(
    request: ImportRequest, mode: PreprocessRequest.Mode = .deepsky, knobs: KnobPatch = KnobPatch(),
    scope: RunScope? = nil
  ) {
    self.request = request
    self.mode = mode
    self.knobs = knobs
    self.scope = scope
  }
}

extension StackRecord {
  /// What the record carries that this build cannot apply, as the panel lists it (`mode=galaxy`).
  package var ignoredEntries: [String] {
    unknownMode.map { ["mode=\($0)"] } ?? []
  }

  /// The run paused at the frame review and the user answered (`ProjectFacts.framesReviewed`).
  package var framesReviewed: Bool { frameReview != nil }

  /// The record `stack` holds in its `params_json`.
  package init(stack: ProjectStack) throws {
    self = try JSONDecoder().decode(Self.self, from: Data(stack.paramsJSON.utf8))
  }
}

extension StackRecord: Codable {
  private enum Key: String, CodingKey {
    case mode, knobs, scope
    case frameReview = "frame_review"
    case referencePins = "reference_pins"
  }

  package init(from decoder: any Decoder) throws {
    request = try ImportRequest(from: decoder)
    let record = try decoder.container(keyedBy: Key.self)
    let recorded = try record.decodeIfPresent(String.self, forKey: .mode)
    mode = recorded.flatMap(PreprocessRequest.Mode.init(rawValue:)) ?? .deepsky
    unknownMode = mode.rawValue == recorded || recorded == nil ? nil : recorded
    knobs = try record.decodeIfPresent(KnobPatch.self, forKey: .knobs) ?? KnobPatch()
    scope = try record.decodeIfPresent(RunScope.self, forKey: .scope)
    frameReview = try record.decodeIfPresent([String: FrameDecision].self, forKey: .frameReview)
    referencePins = try record.decodeIfPresent([String: Int].self, forKey: .referencePins)
  }

  package func encode(to encoder: any Encoder) throws {
    try request.encode(to: encoder)
    var record = encoder.container(keyedBy: Key.self)
    try record.encode(mode, forKey: .mode)
    if !knobs.values.isEmpty { try record.encode(knobs, forKey: .knobs) }
    try record.encodeIfPresent(scope, forKey: .scope)
    try record.encodeIfPresent(frameReview, forKey: .frameReview)
    try record.encodeIfPresent(referencePins, forKey: .referencePins)
  }
}
