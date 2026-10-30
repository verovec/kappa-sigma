package import AppKit
package import Foundation
internal import OSLog
internal import ProcessKit
package import ProjectKit
package import StackKit
internal import SwiftUI

/// An AstroStack project document: an `NSDocument` over a `.astrostack` package.
///
/// The package is edited in place (ProjectKit/README.md): saving checkpoints `project.db` instead
/// of NSDocument's default safe-save, which would rewrite the whole package on every save. An
/// untitled document lives in a temporary package until its first save moves it.
package final class ProjectDocument: NSDocument {
  /// Called once the last project has closed (card 0144), `quietly` for a relaunch's or a quit's
  /// closes: the app brings the welcome window back after a plain close, so ⌘W never leaves it
  /// windowless; `AppDelegate` arms it at launch.
  package static var lastDocumentClosed: @MainActor (_ quietly: Bool) -> Void = { _ in }
  /// The documents still open after a close: the shared controller's (a test counts only its own).
  package static var openDocuments: @MainActor () -> [NSDocument] = {
    NSDocumentController.shared.documents
  }
  /// Set while `closeQuietly` closes.
  private static var closingQuietly = false

  /// Closes `documents` for a relaunch or a quit: the last close says so (`quietly`).
  package static func closeQuietly(_ documents: [NSDocument]) {
    let outer = closingQuietly
    closingQuietly = true
    defer { closingQuietly = outer }
    for document in documents { document.close() }
  }

  private var project: ProjectPackage?
  private var isTemporary = false
  /// The window's model, so closing the project stops a run that writes into it.
  package private(set) var windowModel: ProjectWindowModel?
  /// The astro folder whose captures, runs, library and fixtures never receive a project (R7,
  /// Settings' choice — card 0148); tests use a fake.
  package var astro: () -> URL = { AstroFolderSetting().folder }

  /// The folder of the package the document currently edits.
  package var packageURL: URL? { project?.url }

  /// The package is the document: there is no separate autosave copy to keep in sync.
  nonisolated override package static var autosavesInPlace: Bool { false }

  /// A new untitled document, backed by a fresh package in the temporary folder.
  package convenience init(type typeName: String) throws {
    self.init()
    fileType = typeName
    // A folder of its own, marked by this process: a crash leaves it to the next launch's sweep
    // (LeftoverSweep), and the marker stays out of the package a Save copies.
    let id = UUID().uuidString
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStack/Untitled/\(id)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // Best effort: without it the folder is swept a day later, never a project that cannot start.
    do {
      try ScratchOwner.mark(folder)
    } catch {
      Self.logger.error("marking \(folder.path) failed: \(error)")
    }
    project = try ProjectPackage.create(
      at: folder.appendingPathComponent(id).appendingPathExtension(ProjectPackage.fileExtension))
    isTemporary = true
  }

  // MARK: - Reading and writing

  // NSDocument declares its I/O hooks nonisolated because a subclass may opt into background
  // reads or writes. This one keeps `canConcurrentlyReadDocuments` and `canAsynchronouslyWrite`
  // at their default (false), so AppKit calls the hooks on the main thread; we assert it.

  /// Opens the package at `url`, then releases the one open before (revert, or an untitled one).
  nonisolated override package func read(from url: URL, ofType typeName: String) throws {
    try MainActor.assumeIsolated {
      // A project left among the captures before card 0101 would get its runs written there.
      try refuseReadOnly(url)
      let opened = try Self.openOwned(url)
      if let project { release(project) }
      project = opened
    }
  }

  /// Saves the package in place, or writes it elsewhere; never NSDocument's safe-save.
  nonisolated override package func writeSafely(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType
  ) throws {
    try MainActor.assumeIsolated { try write(to: url, for: saveOperation) }
  }

  /// Saves in place, or copies the package to `url` and possibly moves the document there.
  ///
  /// Save on a titled project checkpoints it in place: AppKit's `url` is the document's own file,
  /// even if the folder moved since it was opened. Any other operation copies the package to
  /// `url`; only Save (first save of an untitled project) and Save As move the document there.
  /// Nothing is written in a folder the app only reads (R7, card 0101), not even in place after a
  /// Finder move there: the export's refusal.
  private func write(to url: URL, for saveOperation: NSDocument.SaveOperationType) throws {
    try refuseReadOnly(url)
    if saveOperation == .saveOperation { try followMove(to: url) }
    guard let project else { throw CocoaError(.fileWriteUnknown) }
    if (saveOperation == .saveOperation && !isTemporary) || Self.isSameFile(project.url, url) {
      try project.save()
      return
    }
    try Self.copy(project, replacing: url)
    guard saveOperation == .saveOperation || saveOperation == .saveAsOperation else { return }
    // Open the copy before letting go of the original: a failure leaves the document intact.
    let moved = try Self.openOwned(url)
    release(project)
    self.project = moved
    // An untitled project just got its name: the window offers Run now.
    windowModel?.refresh()
  }

  /// Throws the export's refusal when the package at `url` (links resolved, the link itself
  /// included) lies under the astro folder's captures, runs, library or fixtures.
  private func refuseReadOnly(_ url: URL) throws {
    guard let reason = ExportGuard.refusal(for: url, astro: astro()) else { return }
    throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: reason])
  }

  /// Follows a move of the package in the Finder as soon as AppKit reports it.
  ///
  /// AppKit sets `fileURL` when its file presenter sees the move. The property is nonisolated in
  /// the SDK; a change off the main thread is left to the next Save, which follows the move too.
  nonisolated override package var fileURL: URL? {
    didSet {
      guard Thread.isMainThread, let url = fileURL else { return }
      MainActor.assumeIsolated {
        do {
          try followMove(to: url)
        } catch {
          Self.logger.error("reopening the moved project at \(url.path) failed: \(error)")
        }
      }
    }
  }

  /// Reopens a titled project's package at `url` when its folder moved there while open: SQLite
  /// derives its WAL paths from the path it opened, so the old pool must not be used any more.
  private func followMove(to url: URL) throws {
    guard let project, !isTemporary, Self.wasMoved(project.url, to: url) else { return }
    let reopened = try Self.openOwned(url)
    release(project)
    self.project = reopened
    // The window's head follows the package (card 0146).
    windowModel?.refresh()
  }

  /// Help › First-Stack Guide: opens this project's guide (card 0061), the only way it opens.
  @objc package func showGuide(_ sender: Any?) {
    windowModel?.openGuide()
  }

  /// File › Export… (⇧⌘E): the Export stage, its form and the exports of the stack (card 0091).
  @objc package func showExport(_ sender: Any?) {
    windowModel?.select(.export)
  }

  // MARK: - The Studio's commands (card 0087)

  /// Edit › Apply Process (⌘E): the open panel's values become a history step.
  @objc package func applyProcess(_ sender: Any?) {
    guard let workspace = windowModel?.workspace else { return }
    // The same move as the panel's button: registered with the window's undo manager; a failure
    // is shown in the panel.
    StudioUndo.apply(workspace, undoManager: undoManager)
  }

  // MARK: - The Tri stage's commands (card 0069)

  /// View › Previous Frame (⌘←): the blink panel one frame back.
  @objc package func blinkPrevious(_ sender: Any?) {
    windowModel?.run?.paused?.blinkPrevious()
  }

  /// View › Next Frame (⌘→).
  @objc package func blinkNext(_ sender: Any?) {
    windowModel?.run?.paused?.blinkNext()
  }

  /// View › Keep Frame (⌘K): the frame shown stays in the stack.
  @objc package func keepFrame(_ sender: Any?) {
    guard let review = windowModel?.run?.paused, let current = review.current else { return }
    review.keep(current)
  }

  /// View › Reject Frame (⌘⌫): the frame shown leaves the stack.
  @objc package func rejectFrame(_ sender: Any?) {
    guard let review = windowModel?.run?.paused, let current = review.current else { return }
    review.reject(current)
  }

  /// View › Continue Stacking (⌘↩): the run goes on with the frames kept.
  @objc package func continueStacking(_ sender: Any?) {
    windowModel?.run?.paused?.continueStacking()
  }

  /// The review commands are greyed unless a run waits at the review on this window; the keys
  /// (⌘←, ⌘→, ⌘⌫, ⌘↩) stay with a text field being edited.
  override package func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool
  {
    if item.action == #selector(applyProcess(_:)) {
      return windowModel?.selection == .studio && windowModel?.workspace?.panel != nil
    }
    if item.action == #selector(showExport(_:)) {
      guard let status = windowModel?.statuses[.export] else { return false }
      if case .unavailable = status { return false }
      return true
    }
    if let action = item.action, Self.pipelineActions.contains(action) {
      return Self.pipelineEnabled(action, in: windowModel)
    }
    if let action = item.action, Self.geometryActions.contains(action) {
      return Self.geometryEnabled(in: windowModel)
    }
    guard let action = item.action, Self.reviewActions.contains(action) else {
      return super.validateUserInterfaceItem(item)
    }
    // Only on the Tri stage: a verdict changed from another pane would be a hidden one (R2).
    guard let windowModel, windowModel.selection == .review,
      let review = windowModel.run?.paused, review.isLive,
      !(NSApp.keyWindow?.firstResponder is NSText)
    else { return false }
    switch action {
    case #selector(continueStacking(_:)): return review.canContinue
    case #selector(keepFrame(_:)), #selector(rejectFrame(_:)):
      return review.currentRow?.isRegistered == true
    default: return true
    }
  }

  private static let reviewActions: [Selector] = [
    #selector(blinkPrevious(_:)), #selector(blinkNext(_:)), #selector(keepFrame(_:)),
    #selector(rejectFrame(_:)), #selector(continueStacking(_:)),
  ]

  /// Records a legacy run opened from this project: its path only, read-only (R7).
  @discardableResult
  package func importLegacyRun(_ source: LegacyRunSource) throws -> ProjectSource {
    guard let project else { throw CocoaError(.fileReadUnknown) }
    let recorded = try source.record(in: project.store)
    // The project changed: an untitled one must offer to be saved, not be discarded silently.
    markEditedIfUntitled()
    return recorded
  }

  /// An untitled project that changed must offer to be saved on close, not be deleted silently;
  /// a titled one is already written in place (`project.db`), nothing is pending.
  private func markEditedIfUntitled() {
    if isTemporary { updateChangeCount(.changeDone) }
  }

  /// The sources the project records; `nil` without an open package.
  package func projectSources() throws -> [ProjectSource]? {
    try project?.store.sources()
  }

  /// The project's counts through its own pool; `nil` without an open package or when unreadable.
  package func projectSummary() -> ProjectSummary? {
    try? project?.store.summary()
  }

  /// Closes the package (deleting an unsaved untitled one) before closing the document.
  override package func close() {
    windowModel?.cancelRun()
    windowModel?.cancelScan()
    // A Studio load still running would write into a package being released (or deleted).
    windowModel?.dropWorkspace()
    // A second close, or one of a document never shown, brings nothing back.
    let wasOpen = Self.openDocuments().contains { $0 === self }
    if let project { release(project) }
    project = nil
    super.close()
    if wasOpen, Self.openDocuments().isEmpty { Self.lastDocumentClosed(Self.closingQuietly) }
  }

  /// True when the folder opened at `opened` is gone and AppKit now names an existing `current`.
  private static func wasMoved(_ opened: URL, to current: URL) -> Bool {
    let manager = FileManager.default
    return !isSameFile(opened, current) && !manager.fileExists(atPath: opened.path)
      && manager.fileExists(atPath: current.path)
  }

  private static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.resolvingSymlinksInPath()
      == rhs.standardizedFileURL.resolvingSymlinksInPath()
  }

  /// Copies the package next to `url`, then swaps it in, so a failed copy never destroys the
  /// package the user chose to replace.
  private static func copy(_ project: ProjectPackage, replacing url: URL) throws {
    // Never over a package another running AstroStack holds (card 0147).
    try refuseHeldElsewhere(url)
    let manager = FileManager.default
    guard manager.fileExists(atPath: url.path) else {
      try project.copy(to: url)
      return
    }
    let staging = try manager.url(
      for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
    defer { try? manager.removeItem(at: staging) }
    let copy = staging.appendingPathComponent(url.lastPathComponent)
    try project.copy(to: copy)
    _ = try manager.replaceItemAt(url, withItemAt: copy)
  }

  /// Closes `project` and deletes it when it was the untitled temporary package.
  ///
  /// Failures are logged, not thrown: the document has already moved on or is closing.
  private func release(_ project: ProjectPackage) {
    let wasTemporary = isTemporary
    isTemporary = false
    do {
      try project.close()
    } catch {
      Self.logger.error("closing \(project.url.path) failed: \(error)")
    }
    guard wasTemporary else { return }
    do {
      try FileManager.default.removeItem(at: project.url)
    } catch {
      Self.logger.error("deleting \(project.url.path) failed: \(error)")
      return
    }
    let folder = project.url.deletingLastPathComponent()
    do {
      try Self.removeUntitledFolder(folder)
    } catch {
      Self.logger.error("deleting \(folder.path) failed: \(error)")
    }
  }

  /// Removes the untitled package's folder once only its marker (and the Finder's files) is
  /// left: a package written there by someone else stays.
  private static func removeUntitledFolder(_ folder: URL) throws {
    let manager = FileManager.default
    let left = Set(try manager.contentsOfDirectory(atPath: folder.path))
      .subtracting(StackLeftovers.finderFiles).subtracting([ScratchOwner.fileName])
    guard left.isEmpty else { return }
    try manager.removeItem(at: folder)
  }

  // MARK: - Window

  /// One window per project, centred; a further project opens as a tab of the frontmost one.
  override package func makeWindowControllers() {
    // A Studio move is refused, not consumed, while a run moves the history (card 0117).
    if !(undoManager is ProjectUndoManager) { undoManager = ProjectUndoManager() }
    let window = NSWindow(
      contentRect: SplitWindow.contentRect(panes: NSSize(width: 960, height: 640)),
      styleMask: SplitWindow.styleMask,
      backing: .buffered, defer: false)
    let model = ProjectWindowModel(
      store: { [weak self] in self?.project?.store }, folder: { [weak self] in self?.project?.url },
      isSaved: { [weak self] in self?.isTemporary == false },
      edited: { [weak self] in self?.markEditedIfUntitled() },
      save: { [weak self] in self?.save(nil) })
    model.undoManager = { [weak self] in self?.undoManager }
    windowModel = model
    let content = NSHostingView(
      rootView: ProjectWindowView(model: model, projects: .live).interfaceLocale())
    // Only the minimum size comes from SwiftUI; the window keeps its own frame.
    content.sizingOptions = [.minSize]
    window.contentView = content
    // Projects share one window as tabs, whatever « Prefer tabs » says; nothing else joins them.
    window.tabbingMode = .preferred
    window.tabbingIdentifier = Self.tabbingIdentifier
    window.center()
    addWindowController(NSWindowController(window: window))
    // A project is open, however it was opened (welcome, ⌘O, Open Recent, Finder, -openRun).
    WelcomeWindow.dismiss()
    Self.logger.info("project window opened: \(window.title, privacy: .public)")
  }

  /// The tab group of project windows: viewers and legacy runs keep their own windows.
  package static let tabbingIdentifier = "fr.astrostack.project"

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/document")
}
