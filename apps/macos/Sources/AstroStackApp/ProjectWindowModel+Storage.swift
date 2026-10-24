package import Foundation
internal import OSLog
internal import ProjectKit
package import StackKit

/// What the project's stacks take on disk (card 0114): a finished run trimmed to its bundle, each
/// stack's size and exports listed, and a stack deleted only when the user says so (R2).
extension ProjectWindowModel {
  /// Trims a finished run's folder to what its bundle reads, the journal saying what went.
  func trimStack(_ stackFolder: URL, bundle: LinearBundle?) async {
    for line in await Self.trimNotes(stackFolder, bundle: bundle) { run?.note(line) }
  }

  /// Trims `stackFolder` to `bundle` (the one the stack opened with, else its `bundle.json`) off
  /// the main actor, and words it for the journal.
  ///
  /// One line per file removed with its size; a trim that fails is one warning line: the stack
  /// is recorded all the same.
  @concurrent
  package nonisolated static func trimNotes(_ stackFolder: URL, bundle: LinearBundle? = nil)
    async -> [String]
  {
    do {
      let bundle = try bundle ?? BundleWriter.read(from: stackFolder)
      return try StackFolder.trim(stackFolder, bundle: bundle).map {
        "trimmed \($0.name) (\($0.bytes) bytes): not read by the bundle"
      }
    } catch {
      return ["⚠ stack folder not trimmed: \(error)"]
    }
  }

  /// Reads every finished stack with its folder's size (off the main actor) and export count.
  ///
  /// Every folder is measured again (the Studio's history grows it): sizes are never cached. A
  /// listing overtaken (cancelled, or a delete while it measured) writes nothing; the rows are
  /// read again once measured, so an opening meanwhile shows.
  package func listStorage() async {
    guard let store = store(), let folder = folder() else { return }
    let deletes = storageDeletes
    do {
      let stacks = try store.stacks().filter { !deletingStacks.contains($0.id) }
      let counts = try store.exportCounts()
      let measured = await Self.measure(stacks, in: folder, counts: counts)
      guard !Task.isCancelled, deletes == storageDeletes else { return }
      let current = Dictionary(try store.stacks().map { ($0.id, $0) }) { first, _ in first }
      storage = measured.compactMap { row in
        current[row.id].map { StackStorageRow(stack: $0, bytes: row.bytes, exports: row.exports) }
      }
    } catch {
      self.error = UserFacingError(error)
    }
  }

  @concurrent
  private nonisolated static func measure(
    _ stacks: [ProjectStack], in folder: URL, counts: [Int64: Int]
  ) async -> [StackStorageRow] {
    stacks.compactMap { stack in
      // A cancelled listing (the stacks changed) stops walking folders of tens of GB.
      guard !Task.isCancelled else { return nil }
      return StackStorageRow(
        stack: stack,
        bytes: LeftoverSweep.allocatedBytes(folder.appendingPathComponent(stack.bundlePath)),
        exports: counts[stack.id] ?? 0)
    }
  }

  /// The stack the Studio reads: the one whose folder it shows, else the workspace loading.
  ///
  /// Matched on the folder's name, never on the selection: with no choice the selection follows
  /// the latest stack while the Studio may still show an older one (`retryWorkspace`); the name
  /// survives a project renamed in the Finder while open.
  package var openStackID: Int64? {
    guard let shown = studio?.source.folder.standardizedFileURL.lastPathComponent else {
      return workspaceStackID
    }
    return stacks.first { ProjectStore.stackFolderName($0.bundlePath) == shown }?.id
      ?? workspaceStackID
  }

  /// True for the stack the Studio reads or is loading: it cannot be deleted.
  package func isStackOpen(_ id: Int64) -> Bool {
    id == openStackID || id == workspaceStackID
  }

  /// Deletes stack `id`, its history and its folder, off the main actor; the stack the Studio
  /// reads (or loads) is refused.
  ///
  /// A deleted chosen stack leaves the choice to the latest; the Storage section re-measures
  /// when the stacks change.
  package func deleteStack(_ id: Int64) async {
    guard !isStacking, let store = store(), let folder = folder() else { return }
    guard !isStackOpen(id) else {
      error = .stackOpen
      return
    }
    // The store's own guard gets the Studio's stack, read while the stack is still listed.
    let open = openStackID
    // Out of the picker and the list before the folder goes: nothing can open it meanwhile.
    stacks.removeAll { $0.id == id }
    storage.removeAll { $0.id == id }
    storageDeletes += 1
    deletingStacks.insert(id)
    defer { deletingStacks.remove(id) }
    do {
      try await Self.delete(id, store: store, folder: folder, open: open)
    } catch {
      // The store as it is now, never a snapshot: another delete may have finished meanwhile.
      deletingStacks.remove(id)
      stacks = (try? store.stacks().filter { !deletingStacks.contains($0.id) }) ?? stacks
      self.error = UserFacingError(error)
      await listStorage()
      return
    }
    stacks = (try? store.stacks()) ?? stacks
    if selectedStackID == id { selectStack(nil) } else { refresh() }
  }

  @concurrent
  private nonisolated static func delete(
    _ id: Int64, store: ProjectStore, folder: URL, open: Int64?
  ) async throws {
    try store.deleteStack(id: id, packageFolder: folder, openStackID: open)
  }

  /// Records that the Studio opened stack `id`: the retention age counts from it.
  ///
  /// The rows shown follow: the Storage section reads « last opened » from them.
  func markOpened(_ id: Int64) {
    do {
      guard let store = store() else { return }
      try store.markStackOpened(id: id)
      guard let marked = try store.stack(id: id) else { return }
      stacks = stacks.map { $0.id == id ? marked : $0 }
      storage = storage.map {
        $0.id == id ? StackStorageRow(stack: marked, bytes: $0.bytes, exports: $0.exports) : $0
      }
    } catch {
      Self.storageLogger.error("stack \(id) not marked opened: \(error)")
    }
  }

  private static let storageLogger = Logger(subsystem: "fr.astrostack", category: "App/storage")
}
