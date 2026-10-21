/// The profile proposed for a capture (card 0060), with its reasons — shown, confirmed or replaced
/// by the user, never applied by itself (R2).
///
/// The camera and the filter composition narrow the profiles; one left is proposed; several are
/// told apart only by a target a profile was validated on; otherwise nothing is proposed and the
/// candidates are listed. The object type is never guessed from pixels: the user knows it.
package struct ProfileProposal: Equatable, Sendable {
  /// What the import knows of the captures.
  package struct Inputs: Equatable, Sendable {
    /// The target's name (folder or run), if any.
    package let object: String?
    /// The camera, `nil` when mixed or unknown.
    package let camera: Profile.Camera?
    /// The filter composition, `nil` when unknown.
    package let filters: Profile.Filters?

    /// The inputs of a capture.
    package init(object: String?, camera: Profile.Camera?, filters: Profile.Filters?) {
      self.object = object
      self.camera = camera
      self.filters = filters
    }
  }

  /// Why a profile is proposed.
  package enum Reason: Equatable, Sendable {
    /// The captures' camera.
    case camera(Profile.Camera)
    /// The captures' filter composition.
    case filters(Profile.Filters)
    /// The target is one this profile was validated on (as the profile names it).
    case object(String)
    /// The only profile for this camera and these filters.
    case onlyMatch
  }

  /// The proposed profile, `nil` when the captures do not single one out.
  package let proposed: Profile?
  /// Why it is proposed (empty when nothing is).
  package let reasons: [Reason]
  /// The profiles that fit the camera and filters, the proposed one among them.
  package let candidates: [Profile]

  /// The proposal for `inputs` among `profiles`.
  package static func propose(_ inputs: Inputs, among profiles: [Profile]) -> Self {
    let candidates = profiles.filter { profile in
      (inputs.camera.map { $0 == profile.camera } ?? true)
        && (inputs.filters.map(profile.filters.contains) ?? true)
    }
    // Without the camera nothing is proposed: an example name alone may be another rig's.
    guard let camera = inputs.camera else {
      return Self(proposed: nil, reasons: [], candidates: candidates)
    }
    var reasons: [Reason] = [.camera(camera)]
    if let filters = inputs.filters { reasons.append(.filters(filters)) }
    let target = inputs.object.map(Self.normalised)
    // The profiles whose validated targets include this one, among all profiles.
    let owners = profiles.filter { profile in
      profile.examples.contains { Self.normalised($0) == target }
    }.map(\.id)
    if candidates.count == 1, inputs.filters != nil {
      // The only match for these captures, unless the target is another profile's (M 31 shot in
      // broadband only is not a cluster): then nothing is proposed.
      guard owners.isEmpty || owners.contains(candidates[0].id) else {
        return Self(proposed: nil, reasons: [], candidates: candidates)
      }
      return Self(proposed: candidates[0], reasons: reasons + [.onlyMatch], candidates: candidates)
    }
    let named = candidates.compactMap { profile in
      profile.examples.first { Self.normalised($0) == target }.map { (profile, $0) }
    }
    if named.count == 1, let (profile, example) = named.first {
      return Self(proposed: profile, reasons: reasons + [.object(example)], candidates: candidates)
    }
    return Self(proposed: nil, reasons: [], candidates: candidates)
  }

  /// `M 31`, `m31` and `M31` are the same target.
  static func normalised(_ name: String) -> String {
    name.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
  }
}
