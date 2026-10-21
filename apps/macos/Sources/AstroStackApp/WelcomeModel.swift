package import Foundation
internal import Observation
package import ProjectKit
package import StackKit

/// What the welcome window shows: the recent projects and the host tools' status.
///
/// It reads and reports only: opening, creating and installing are the window's buttons.
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

    /// The tool.
    package var id: HostTool { tool }
  }

  /// The recent projects, most recent first; deleted ones are left out.
  package private(set) var recent: [RecentProject] = []
  /// Every host tool, once checked; empty before the first check.
  package private(set) var tools: [ToolRow] = []

  private let recentURLs: () -> [URL]
  private let hostTools: HostTools

  /// A model listing `recentURLs` (the document controller's) and checking `tools`.
  package init(recentURLs: @escaping () -> [URL], tools: HostTools) {
    self.recentURLs = recentURLs
    self.hostTools = tools
  }

  /// Reads the recent projects again.
  package func reload() {
    recent = recentURLs()
      .filter { FileManager.default.fileExists(atPath: $0.path) }
      .map { url in
        RecentProject(
          url: url, target: url.deletingPathExtension().lastPathComponent,
          summary: Self.summary(of: url))
      }
  }

  /// Probes every host tool, in the catalogue's order.
  package func recheckTools() async {
    var rows: [ToolRow] = []
    for tool in HostTool.allCases {
      rows.append(ToolRow(tool: tool, status: await hostTools.locate(tool)))
    }
    tools = rows
  }

  /// The counts of the package at `url`, or `nil` when it cannot be opened.
  private static func summary(of url: URL) -> ProjectSummary? {
    guard let package = try? ProjectPackage.open(at: url) else { return nil }
    defer { try? package.close() }
    return try? package.store.summary()
  }
}
