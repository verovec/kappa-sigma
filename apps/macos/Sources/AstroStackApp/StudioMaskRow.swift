internal import ProcessKit
internal import RenderKit
internal import SwiftUI

/// Where the chosen process acts (card 0087): everywhere, a luminosity range or the stars,
/// inverted or not — applied by the kit after the process, to the preview and Apply alike.
struct StudioMaskRow: View {
  let model: StudioWorkspaceModel

  /// The mask sources the row offers.
  enum Source: String, CaseIterable {
    case none, luminosity, stars

    var mask: MaskSource? {
      switch self {
      case .none: nil
      case .luminosity: .luminosityRange(low: 0.2, high: 1, softness: 0.1)
      case .stars: .stars(threshold: 0.02, radiusPx: 8)
      }
    }

    var title: LocalizedStringResource {
      switch self {
      case .none: .app("No mask")
      case .luminosity: .app("Luminosity")
      case .stars: .app("Stars")
      }
    }

    init(_ mask: Mask?) {
      switch mask?.source {
      case nil: self = .none
      case .luminosityRange: self = .luminosity
      case .stars: self = .stars
      }
    }
  }

  var body: some View {
    HStack {
      Picker(selection: source) {
        ForEach(Source.allCases, id: \.self) { Text($0.title).tag($0) }
      } label: {
        Text(.app("Mask"))
      }
      .accessible(.studioMaskSource, label: .app("Mask"))
      Toggle(isOn: inverted) { Text(.app("Invert")) }
        .disabled(model.mask == nil)
        .accessible(.studioMaskInvert, label: .app("Invert"))
    }
  }

  private var source: Binding<Source> {
    Binding(
      get: { Source(model.mask) },
      set: { choice in
        model.mask = choice.mask.map { Mask(source: $0, inverted: model.mask?.inverted ?? false) }
      })
  }

  private var inverted: Binding<Bool> {
    Binding(
      get: { model.mask?.inverted ?? false },
      set: { model.mask?.inverted = $0 })
  }
}
