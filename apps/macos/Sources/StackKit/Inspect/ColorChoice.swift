internal import Foundation

/// The user's colour-model knob (`inspect.ColorChoice`): not a `ColorModel` — no `mixed` (nobody
/// asks for an unstackable folder) and an `auto` that defers to the scan's verdict.
package enum ColorChoice: String, CaseIterable, Sendable {
  case auto
  case mono
  case osc

  /// Validates a wire value; empty is `auto`.
  package init(parsing raw: String) throws {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let choice = value.isEmpty ? .auto : Self(rawValue: value) else {
      throw InspectError.unknownColorChoice(raw)
    }
    self = choice
  }
}

extension Inventory {
  /// Applies an explicit colour choice (`ResolveColorModel`): drops the contradicting LIGHTS
  /// (calibration frames carry no colour identity in the matcher), rewrites the verdict and names
  /// surviving colour lights. `auto` is a deliberate no-op. Throws when no light matches.
  package mutating func resolve(_ choice: ColorChoice) throws {
    guard choice != .auto else { return }
    let hadLights = frames.contains { $0.type == .light }
    let before = frames.count
    if choice == .mono {
      // Same as a mixed folder in a mono run: a frame still CFA after the veto is the colour rig's.
      frames.removeAll(where: \.isColor)
    } else {
      frames.removeAll { $0.type == .light && !$0.isColor }
    }
    let removed = before - frames.count
    if hadLights && !frames.contains(where: { $0.type == .light }) {
      throw InspectError.noLightsForColorModel(choice: choice.rawValue, dropped: removed)
    }
    colorModel = choice == .mono ? .mono : .osc
    var renamed = 0
    for index in frames.indices
    where frames[index].type == .light && frames[index].isColor && frames[index].filter.isEmpty {
      frames[index].filter = Filter.color
      renamed += 1
    }
    if removed > 0 || renamed > 0 { regroup() }
    if removed > 0 {
      let dropped = choice == .mono ? "one-shot-color" : "monochrome"
      let label = choice == .mono ? "monochrome stack" : "colour stack"
      warnings.append("\(removed) \(dropped) light frame(s) excluded — this run was submitted as a \(label)")
    }
  }

  /// Remaps light filters to user-chosen channels; `""` or `ignore` takes the lights out of every
  /// set (`ApplyFilterMapping`).
  package mutating func applyFilterMapping(_ mapping: [String: String]) {
    guard !mapping.isEmpty else { return }
    for index in frames.indices where frames[index].type == .light {
      guard let target = mapping[frames[index].filter] else { continue }
      if target.isEmpty || target == "ignore" {
        frames[index].type = .unknown
      } else {
        frames[index].filter = Filter.normalize(target)
        frames[index].classSource = .manual
      }
    }
    regroup()
  }
}
