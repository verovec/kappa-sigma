package import StackKit

/// What the master disclosure of the Import sheet does beyond planning: measure a master, rebuild
/// one into the library, open it in the viewer (card 0071).
package nonisolated struct MasterServices: Sendable {
  /// Rebuilds the master of a capture set into the library, streaming Siril's lines; without
  /// `replace` an existing library file throws `CalibrationError.wouldReplace`.
  package typealias Rebuild =
    @Sendable (
      _ set: FrameSet, _ inventory: Inventory, _ pool: [CalibrationMaster], _ replace: Bool,
      _ onLine: @escaping @Sendable (SirilLine) -> Void
    ) async throws -> MasterBuilder.Result

  /// Reads and measures a master, off the main actor.
  package var inspect: @Sendable (String) async throws -> MasterInspection
  package var rebuild: Rebuild
  /// Shows a master in the Metal viewer (STF).
  package var preview: @MainActor @Sendable (String) -> Void

  /// The services from their closures (tests record the calls).
  package init(
    inspect: @escaping @Sendable (String) async throws -> MasterInspection,
    rebuild: @escaping Rebuild,
    preview: @escaping @MainActor @Sendable (String) -> Void
  ) {
    self.inspect = inspect
    self.rebuild = rebuild
    self.preview = preview
  }
}
