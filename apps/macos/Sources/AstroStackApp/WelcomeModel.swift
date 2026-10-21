package import Foundation
internal import Observation
package import ProjectKit
package import RenderKit
package import StackKit

/// What the welcome window shows: the recent projects and the host tools' status.
///
/// It reads and reports only: opening, creating and installing are the window's buttons. A
/// project open in a document is never opened a second time: its counts come from that document,
/// since a second pool on its `project.db` would checkpoint and delete the WAL under it.
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
  private let openProjects: @MainActor () -> [URL: ProjectSummary?]
  private let hostTools: HostTools
  private var isChecking = false

  /// A model listing `recentURLs` (the document controller's) and checking `tools`;
  /// `openProjects` gives the counts of the projects open in a document, by standardized URL.
  package init(
    recentURLs: @escaping @MainActor () -> [URL], tools: HostTools,
    openProjects: @escaping @MainActor () -> [URL: ProjectSummary?] = { [:] }
  ) {
    self.recentURLs = recentURLs
    self.openProjects = openProjects
    self.hostTools = tools
  }

  /// Reads the recent projects again; packages are read off the main actor.
  package func reload() async {
    let open = openProjects()
    var rows: [RecentProject] = []
    for url in recentURLs() where FileManager.default.fileExists(atPath: url.path) {
      let key = url.standardizedFileURL
      let summary = open.keys.contains(key) ? open[key] ?? nil : await Self.readSummary(url)
      rows.append(
        RecentProject(
          url: url, target: url.deletingPathExtension().lastPathComponent, summary: summary))
    }
    recent = rows
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
    cards = Dictionary(
      uniqueKeysWithValues: tools.map { row in
        (
          row.tool,
          InstallCardModel(
            state: Self.cardState(row.status), locate: Self.locator(row.tool, hostTools))
        )
      })
  }

  /// The install card state of `status`.
  nonisolated package static func cardState(_ status: ToolStatus) -> InstallCardModel.State {
    switch status {
    case .found(let path, _): .found(URL(fileURLWithPath: path))
    case .missing: .missing
    case .tooOld(_, let version): .outdated(version: version)
    }
  }

  /// An install card's re-check: the tool's path once it is usable.
  nonisolated package static func locator(_ tool: HostTool, _ hostTools: HostTools)
    -> @Sendable @concurrent () async -> URL?
  {
    { @concurrent in
      let status = await hostTools.locate(tool)
      return status.isUsable ? URL(fileURLWithPath: status.path) : nil
    }
  }

  /// The counts of the package at `url` (not open in any document), or `nil` when unreadable.
  @concurrent
  private nonisolated static func readSummary(_ url: URL) async -> ProjectSummary? {
    guard let package = try? ProjectPackage.open(at: url) else { return nil }
    defer { try? package.close() }
    return try? package.store.summary()
  }
}
