internal import RenderKit

/// The viewer's stretch on one history (card 0119): a line layer is mono, its stretch its own.
struct ViewerStretch {
  let stretch: ViewerModel.Stretch
  let linked: Bool
  let manual: [STFParameters]
}
