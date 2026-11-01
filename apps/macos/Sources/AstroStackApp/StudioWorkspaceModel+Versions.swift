package import Foundation
internal import ImageKit
package import ProcessKit

// MARK: - The history versions (card 0159)

extension StudioWorkspaceModel {
  /// The glossary term of the Versions menu.
  package nonisolated static let versionTermID = "studio.version"

  /// The chains a revise or a restore put aside, oldest first: what the Versions menu lists.
  package var versions: [History.Version] {
    studio.session.history.versions
  }

  /// The bytes dropping version `id` frees (shown before the drop is confirmed); 0 when unknown.
  package func bytes(ofVersion id: String) -> Int {
    (try? studio.session.history.bytes(ofVersion: id)) ?? 0
  }

  /// What the Drop confirmation says of version `id` in `locale`: the disk it frees, and that
  /// ⌘Z forgets the combined image's moves.
  package func dropMessage(_ id: String, locale: Locale) -> LocalizedStringResource {
    let size = AstroFormat(locale: locale).bytes(Int64(bytes(ofVersion: id)))
    return .app(
      "Deletes its steps and files (\(size)); ⌘Z forgets the combined image.", locale: locale)
  }

  /// Compares the viewer with the image version `id` ended on, or stops when it is the one
  /// compared; a version on another grid is refused like a step (a failure is reported).
  package func toggleCompare(version id: String) {
    do {
      guard comparingVersion != id else { return try compare(toStep: nil) }
      // A version holds combined-image steps: beside a branch's head it means nothing.
      guard selection == .main else {
        failure = .app("A version holds the combined image's steps: show it to compare.")
        return
      }
      guard !showsMovedGrid else { throw UserFacingError.movedPreview }
      let image = try studio.session.history.head(ofVersion: id)
      guard image.width == head.width, image.height == head.height else {
        throw StudioError.otherGrid(step: versions.first { $0.id == id }?.base ?? 0)
      }
      viewer.reference = try Self.texture(image, device: studio.session.device)
      comparing = nil
      comparingWith = nil
      comparingVersion = id
    } catch {
      failure = UserFacingError(error).message
    }
  }
}

extension StudioUndo {
  /// Puts version `id` back in place of the steps from its base, as one move.
  ///
  /// `StudioModel.restoreVersion`: ⌘Z puts the chain it replaced back. Refused, with its reason,
  /// while a history moves or on a layer's branch.
  package static func restoreVersion(
    _ model: StudioWorkspaceModel, _ id: String, on undoManager: UndoManager?
  ) {
    if let refusal = model.historyMoveRefusal {
      model.failure = refusal
      return
    }
    guard let base = model.versions.first(where: { $0.id == id })?.base else {
      model.failure = UserFacingError(HistoryError.unknownVersion(id)).message
      return
    }
    // The column as it was: ⌘Z puts its recipes back with the chain, as for a revise.
    let mark = model.pipeline.map { $0.mark(keeping: base..<$0.pipeline.steps.count) }
    let replaced: String?
    do {
      replaced = try model.studio.restoreVersion(id)
      model.failure = nil
    } catch {
      // Refused before anything moved: the open panel and the compare stay as they were.
      model.failure = UserFacingError(error).message
      return
    }
    model.closePanel()
    try? model.compare(toStep: nil)
    // The column's steps take the restored values, like a revise's.
    let steps = model.studio.steps
    var touched = false
    for index in steps.indices where index >= base {
      touched = (model.pipeline?.revised(index, params: steps[index].params) ?? false) || touched
    }
    // The history moved: its undo is registered even when the new head cannot be shown.
    do {
      try model.headChanged()
    } catch {
      model.failure = UserFacingError(error).message
    }
    // Nothing put aside (the version sat past the head): no swap to undo.
    guard let replaced else { return }
    recordNew(
      model, steps: 0, in: .main, name: .app("Restore Version"), mark: touched ? mark : nil,
      version: replaced, on: undoManager)
  }

  /// Forgets version `id` and its files, after the user confirmed (no undo).
  ///
  /// The Studio's ⌘Z moves of the combined image are forgotten with it: one of them may swap
  /// that version back, and would fail on it.
  package static func dropVersion(
    _ model: StudioWorkspaceModel, _ id: String, on undoManager: UndoManager?
  ) {
    if let refusal = model.historyMoveRefusal {
      model.failure = refusal
      return
    }
    if let refusal = dropRefusal(model, id) {
      model.failure = refusal
      return
    }
    if model.comparingVersion == id { try? model.compare(toStep: nil) }
    do {
      try model.studio.dropVersion(id)
    } catch {
      model.failure = UserFacingError(error).message
      return
    }
    forgetMoves(model, in: .main, on: undoManager)
  }

  /// Why version `id` cannot be dropped now, or `nil`: ▶ Run still needs the masks it recorded
  /// for the steps a revise left pending (a drop would run them unmasked, R2).
  package static func dropRefusal(_ model: StudioWorkspaceModel, _ id: String)
    -> LocalizedStringResource?
  {
    guard model.versions.last?.id == id, let pipeline = model.pipeline else { return nil }
    let start = model.studio.steps.count
    let planned = pipeline.pipeline.steps.map(\.recipe.processID)
    let needed: Bool
    do {
      needed = try !model.studio.pendingMaskSteps(from: start, planned: planned).isEmpty
    } catch {
      // A check that fails (a mask a moving revise would misplace) refuses too: no silent loss.
      needed = true
    }
    return needed
      ? .app("▶ Run still needs the masks this version recorded: run the pending steps first.")
      : nil
  }
}
