package import Foundation
internal import Observation
package import ProjectKit

/// Every project the app can find (card 0145): the open ones, AppKit's recents and the projects
/// folder, one entry each — a project that fell off the recents still shows.
///
/// It reads and reports only, like `WelcomeModel`: a listed project is read through a read-only
/// connection (never migrated nor checkpointed), one open in a document is counted by that
/// document, and nothing is opened unasked (R2). The folder is the list: no database of projects,
/// no scan beyond `NewProject.projectsFolder` (R7).
@Observable
package final class ProjectCatalog {
  /// Where a project was found; a project in several places is listed under the first.
  package enum Origin: Equatable, Sendable {
    /// Open in a document.
    case open
    /// In AppKit's recent documents.
    case recent
    /// Only in the projects folder.
    case folder
  }

  /// A project as listed: its target, where it was found and, when it could be read, its counts.
  package struct Entry: Equatable, Identifiable {
    /// The package.
    package let url: URL
    /// The target the project is named after (the package name).
    package let target: String
    /// Sources and stacks recorded; `nil` when the package cannot be read.
    package let summary: ProjectSummary?
    /// Where it was found.
    package let origin: Origin

    /// The package's URL.
    package var id: URL { url }
  }

  /// Open projects (document order), then recents (AppKit's order), then the rest of the folder
  /// by target name; a deleted recent is left out.
  package private(set) var entries: [Entry] = []

  private let openProjects: @MainActor () -> [(URL, ProjectSummary?)]
  private let recentURLs: @MainActor () -> [URL]
  private let folderURLs: @Sendable () -> [URL]
  /// The latest `reload()`: an older one finishing late does not overwrite it.
  private var generation = 0

  /// A catalog of `openProjects` (each with its document's counts), `recentURLs` and
  /// `folderURLs` (listed off the main actor: a disk folder may be slow).
  package init(
    openProjects: @escaping @MainActor () -> [(URL, ProjectSummary?)],
    recentURLs: @escaping @MainActor () -> [URL],
    folderURLs: @escaping @Sendable () -> [URL]
  ) {
    self.openProjects = openProjects
    self.recentURLs = recentURLs
    self.folderURLs = folderURLs
  }

  /// Lists the projects again; packages not open are read off the main actor, side by side.
  package func reload() async {
    generation += 1
    let current = generation
    // A package deleted or moved under its open document has nothing left to open.
    let all = openProjects()
    let present = Set(WelcomeModel.onDisk(all.map(\.0)))
    let open = all.filter { present.contains($0.0) }
    var seen = Set(open.map { WelcomeModel.key($0.0) })
    let recent = WelcomeModel.onDisk(recentURLs()).filter {
      seen.insert(WelcomeModel.key($0)).inserted
    }
    let listed = await Self.list(folderURLs)
    let folder = listed.filter { seen.insert(WelcomeModel.key($0)).inserted }.sorted {
      ProjectPackage.target(of: $0).localizedStandardCompare(ProjectPackage.target(of: $1))
        == .orderedAscending
    }
    let read = await withTaskGroup(of: (URL, ProjectSummary?).self) { group in
      for url in recent + folder {
        group.addTask { (url, await Self.readSummary(url)) }
      }
      var read: [URL: ProjectSummary?] = [:]
      for await (url, summary) in group { read[url] = summary }
      return read
    }
    guard current == generation else { return }
    entries =
      open.map { Self.entry($0.0, $0.1, .open) }
      + recent.map { Self.entry($0, read[$0] ?? nil, .recent) }
      + folder.map { Self.entry($0, read[$0] ?? nil, .folder) }
  }

  /// The project packages directly in `folder`: `*.astrostack` directories (a symlink to one
  /// included), hidden ones left out; nothing for a missing folder.
  nonisolated package static func folderListing(of folder: URL) -> [URL] {
    let listed =
      (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])) ?? []
    return listed.filter { url in
      url.pathExtension.lowercased() == ProjectPackage.fileExtension
        && (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
          .isDirectory) == true
    }
  }

  @concurrent
  private nonisolated static func list(_ urls: @Sendable () -> [URL]) async -> [URL] {
    urls()
  }

  private static func entry(_ url: URL, _ summary: ProjectSummary?, _ origin: Origin) -> Entry {
    Entry(url: url, target: ProjectPackage.target(of: url), summary: summary, origin: origin)
  }

  /// The counts of the package at `url`, read-only (never migrated nor checkpointed), or `nil`
  /// when unreadable.
  @concurrent
  private nonisolated static func readSummary(_ url: URL) async -> ProjectSummary? {
    try? ProjectPackage.readSummary(at: url)
  }
}
