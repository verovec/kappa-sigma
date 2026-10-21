package import AppKit

/// The two appearances every token defines a colour for.
package enum DesignAppearance: CaseIterable, Sendable {
  /// Aqua.
  case light
  /// Dark Aqua.
  case dark

  /// The appearance `appearance` draws as (vibrant and high-contrast variants included).
  package init(_ appearance: NSAppearance) {
    self = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }

  /// The AppKit appearance, for offscreen renders and resolution.
  package var nsAppearance: NSAppearance {
    let name: NSAppearance.Name = self == .dark ? .darkAqua : .aqua
    return NSAppearance(named: name) ?? NSAppearance.currentDrawing()
  }
}
