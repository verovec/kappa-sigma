package import Foundation
internal import Observation
package import ProjectKit
package import RenderKit
package import StackKit

/// What the welcome window shows: every project on disk (`catalog`, card 0145) and the host
/// tools' status.
///
/// It reads and reports only: opening, creating and installing are the window's buttons.
@Observable
package final class WelcomeModel {
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

  /// The projects listed: open, recent, then the rest of the projects folder.
  package let catalog: ProjectCatalog
  /// Every host tool, once checked; empty before the first check.
  package private(set) var tools: [ToolRow] = []
  /// The install card of each tool, kept across redraws and shared by every window showing it.
  package private(set) var cards: [HostTool: InstallCardModel] = [:]
  /// Whether the « New Project… » sheet is up (File › New Project raises it too).
  package var isNaming = false

  private let hostTools: HostTools
  private var isChecking = false

  /// A model listing `recentURLs` (the document controller's), `folderURLs` (the projects
  /// folder's packages) and `openProjects` (each open document's package and counts), and checking
  /// `tools`.
  package init(
    recentURLs: @escaping @MainActor () -> [URL], tools: HostTools,
    openProjects: @escaping @MainActor () -> [(URL, ProjectSummary?)] = { [] },
    folderURLs: @escaping @Sendable () -> [URL] = { [] }
  ) {
    catalog = ProjectCatalog(
      openProjects: openProjects, recentURLs: recentURLs, folderURLs: folderURLs)
    self.hostTools = tools
  }

  /// Lists the projects again (`ProjectCatalog.reload`).
  package func reload() async {
    await catalog.reload()
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

  /// The projects of `urls` still on disk: a deleted recent is left out (welcome window, File ›
  /// Open Recent).
  nonisolated package static func onDisk(_ urls: [URL]) -> [URL] {
    urls.filter { FileManager.default.fileExists(atPath: $0.path) }
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
    case .cannotRun(let path, _):
      // StackKit's reason is English for the log; ExecutableCheck refuses only an Intel build
      // without Rosetta, so the card says that in the user's language.
      .unusable(path: URL(fileURLWithPath: path), reason: String(localized: rosettaFix()))
    }
  }

  /// What to do about an Intel-only tool on a Mac without Rosetta (card 0108).
  nonisolated package static func rosettaFix(locale: Locale? = nil) -> LocalizedStringResource {
    .app(
      "Install Rosetta (\(ExecutableCheck.rosettaCommand)) or an Apple-silicon build.",
      locale: locale)
  }

  /// An install card's re-check: the tool probed again, as the card shows it; StarNet as the
  /// separation would find it, so the welcome window and the Export stage agree.
  nonisolated package static func check(_ tool: HostTool, _ hostTools: HostTools)
    -> @Sendable @concurrent () async -> InstallCardModel.State
  {
    if tool == .starnet { return StarSeparation.check(hostTools) }
    return { @concurrent in cardState(await hostTools.locate(tool)) }
  }
}
