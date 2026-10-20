import StackKit

extension PreprocessSettings {
  /// The deepsky preset as the 0044 recorder ran it: the cross-frame trail mask off
  /// (`TrailMaskK: 0` in every recorded case's `stages.json`, "trail mask 0" in its manifest).
  static var recorded: Self {
    var settings = Self()
    settings.trailMaskK = 0
    return settings
  }
}
