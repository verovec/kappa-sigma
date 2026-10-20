package import AppKit
package import Foundation
internal import OSLog
internal import ProjectKit
internal import SwiftUI

/// An AstroStack project document: an `NSDocument` over a `.astrostack` package.
///
/// The package is edited in place (ProjectKit/README.md): saving checkpoints `project.db` instead
/// of NSDocument's default safe-save, which would rewrite the whole package on every save. An
/// untitled document lives in a temporary package until its first save moves it.
package final class ProjectDocument: NSDocument {
  private var project: ProjectPackage?
  private var isTemporary = false

  /// The folder of the package the document currently edits.
  package var packageURL: URL? { project?.url }

  /// The package is the document: there is no separate autosave copy to keep in sync.
  nonisolated override package static var autosavesInPlace: Bool { false }

  /// A new untitled document, backed by a fresh package in the temporary folder.
  package convenience init(type typeName: String) throws {
    self.init()
    fileType = typeName
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStack/Untitled", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    project = try ProjectPackage.create(
      at: folder.appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ProjectPackage.fileExtension))
    isTemporary = true
  }

  // MARK: - Reading and writing

  // NSDocument declares its I/O hooks nonisolated because a subclass may opt into background
  // reads or writes. This one keeps `canConcurrentlyReadDocuments` and `canAsynchronouslyWrite`
  // at their default (false), so AppKit calls the hooks on the main thread; we assert it.

  /// Opens the package at `url`, then releases the one open before (revert, or an untitled one).
  nonisolated override package func read(from url: URL, ofType typeName: String) throws {
    try MainActor.assumeIsolated {
      let opened = try ProjectPackage.open(at: url)
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
  private func write(to url: URL, for saveOperation: NSDocument.SaveOperationType) throws {
    if saveOperation == .saveOperation { try followMove(to: url) }
    guard let project else { throw CocoaError(.fileWriteUnknown) }
    if (saveOperation == .saveOperation && !isTemporary) || Self.isSameFile(project.url, url) {
      try project.save()
      return
    }
    try Self.copy(project, replacing: url)
    guard saveOperation == .saveOperation || saveOperation == .saveAsOperation else { return }
    // Open the copy before letting go of the original: a failure leaves the document intact.
    let moved = try ProjectPackage.open(at: url)
    release(project)
    self.project = moved
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
    let reopened = try ProjectPackage.open(at: url)
    release(project)
    self.project = reopened
  }

  /// Closes the package (deleting an unsaved untitled one) before closing the document.
  override package func close() {
    if let project { release(project) }
    project = nil
    super.close()
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
    }
  }

  // MARK: - Window

  /// One window per project, centred; the window controller cascades further ones.
  override package func makeWindowControllers() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    let content = NSHostingView(rootView: ProjectWindowView())
    // Only the minimum size comes from SwiftUI; the window keeps its own frame.
    content.sizingOptions = [.minSize]
    window.contentView = content
    window.center()
    addWindowController(NSWindowController(window: window))
    Self.logger.info("project window opened: \(window.title, privacy: .public)")
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/document")
}
