package import Foundation
internal import Observation
package import ProjectKit
package import RenderKit
package import StackKit

/// What the welcome window shows: the recent projects and the host tools' status.
///
/// It reads and reports only: opening, creating and installing are the window's buttons. A recent
/// project is read through a read-only connection (never migrated nor checkpointed); one open in
/// a document is counted by that document.
@Observable
package final class WelcomeModel {
  /// A recent project as listed: its target and, when it could be read, its counts.
  package struct RecentProject: Equatable, Identifiable {
    /// The package.
    package let url: URL
    /// The target the project is named after (the package name).
    package let target: String
    /// Sources and stacks recorded; `nil` when the package cannot be read.
    package let summary: ProjectSummary?

    /// The package's URL.
    package var id: URL { url }
  }

  /// One host tool and what was found of it.
  package struct ToolRow: Equatable, Identifiable {
    /// The tool.
    package let tool: HostTool
    /// Its status at the last check.
    package let status: ToolStatus

    /// `tool` found as `status`.
    package init(tool: HostTool, status: ToolStatus) {
      self.tool = tool
      self.status = status
    }

    /// The tool.
    package var id: HostTool { tool }
  }

  /// The recent projects, most recent first; deleted ones are left out.
  package private(set) var recent: [RecentProject] = []
  /// Every host tool, once checked; empty before the first check.
  package private(set) var tools: [ToolRow] = []
  /// The install card of each tool, kept across redraws and shared by every window showing it.
  package private(set) var cards: [HostTool: InstallCardModel] = [:]
  /// Whether the « New Project… » sheet is up (File › New Project raises it too).
  package var isNaming = false

  private let recentURLs: @MainActor () -> [URL]
  private let openProjects: @MainActor () -> [String: ProjectSummary?]
  private let hostTools: HostTools
  private var isChecking = false

  /// A model listing `recentURLs` (the document controller's) and checking `tools`;
  /// `openProjects` gives the counts of the projects open in a document, by `key(_:)`.
  package init(
    recentURLs: @escaping @MainActor () -> [URL], tools: HostTools,
    openProjects: @escaping @MainActor () -> [String: ProjectSummary?] = { [:] }
  ) {
    self.recentURLs = recentURLs
    self.openProjects = openProjects
    self.hostTools = tools
  }

  /// Reads the recent projects again; packages are read off the main actor, side by side.
  package func reload() async {
    let open = openProjects()
    let urls = recentURLs().filter { FileManager.default.fileExists(atPath: $0.path) }
    let read = await withTaskGroup(of: (URL, ProjectSummary?).self) { group in
      for url in urls where !open.keys.contains(Self.key(url)) {
        group.addTask { (url, await Self.readSummary(url)) }
      }
      var read: [URL: ProjectSummary?] = [:]
      for await (url, summary) in group { read[url] = summary }
      return read
    }
    recent = urls.map { url in
      let summary = open[Self.key(url)] ?? read[url] ?? nil
      return RecentProject(
        url: url, target: url.deletingPathExtension().lastPathComponent, summary: summary)
    }
  }

  /// Probes every host tool at once; a check already running is not doubled.
  package func recheckTools() async {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    let found = await withTaskGroup(of: (HostTool, ToolStatus).self) { group in
      for tool in HostTool.allCases {
        group.addTask { [hostTools] in (tool, await hostTools.locate(tool)) }
      }
      var found: [HostTool: ToolStatus] = [:]
      for await (tool, status) in group { found[tool] = status }
      return found
    }
    tools = HostTool.allCases.compactMap { tool in
      found[tool].map { ToolRow(tool: tool, status: $0) }
    }
    for row in tools {
      if let card = cards[row.tool] {
        card.show(Self.cardState(row.status))
      } else {
        cards[row.tool] = InstallCardModel(
          state: Self.cardState(row.status), check: Self.check(row.tool, hostTools))
      }
    }
  }

  /// The key an open project is looked up by: its path with symlinks resolved and no trailing
  /// slash, so `/var/…` and `/private/var/…/M 31.astrostack/` name the same package.
  nonisolated package static func key(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
  }

  /// The install card state of `status`.
  nonisolated package static func cardState(_ status: ToolStatus) -> InstallCardModel.State {
    switch status {
    case .found(let path, _): .found(URL(fileURLWithPath: path))
    case .missing: .missing
    case .tooOld(_, let version): .outdated(version: version)
    }
  }

  /// An install card's re-check: the tool probed again, as the card shows it.
  nonisolated package static func check(_ tool: HostTool, _ hostTools: HostTools)
    -> @Sendable @concurrent () async -> InstallCardModel.State
  {
    { @concurrent in cardState(await hostTools.locate(tool)) }
  }

  /// The counts of the package at `url`, read-only (never migrated nor checkpointed), or `nil`
  /// when unreadable.
  @concurrent
  private nonisolated static func readSummary(_ url: URL) async -> ProjectSummary? {
    try? ProjectPackage.readSummary(at: url)
  }
}
