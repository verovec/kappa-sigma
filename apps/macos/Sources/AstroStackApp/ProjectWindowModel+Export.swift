internal import Foundation

// MARK: - The Export stage (card 0091)

extension ProjectWindowModel {
  /// Opens the Export stage of stack `stackID` over its Studio `studio`: a StarNet step shows in
  /// the Studio, an export marks the stage done.
  func showExport(of studio: StudioModel, stackID: Int64, folder: URL) {
    guard let store = store(), let stack = stacks.first(where: { $0.id == stackID }) else {
      return
    }
    exportStage = ExportStageModel(
      studio: studio, stack: stack, store: store,
      packageFolder: { [weak self] in self?.folder() ?? folder }, services: exportServices,
      onSeparated: { [weak self] in
        // A StarNet step: the Studio shows it, an untitled project asks to be saved.
        self?.recorded()
        do {
          try self?.workspace?.headChanged()
        } catch {
          // After the refresh, which clears the window's error.
          self?.error = UserFacingError(error)
        }
      },
      onExported: { [weak self] in self?.recorded() })
  }

  /// The project changed: the stage states follow, an untitled project asks to be saved.
  private func recorded() {
    edited()
    refresh()
  }

  /// Another stack, or none: a separation still running is stopped.
  func dropExport() {
    exportStage?.cancelSeparation()
    exportStage = nil
  }

  /// « Separate Stars » from the Studio: on the Export stage, whose sheet holds the window while
  /// StarNet runs (a step applied meanwhile would be overtaken by StarNet's).
  func separateStarsFromStudio() {
    guard let exportStage else { return }
    select(.export)
    exportStage.startSeparation()
  }
}
