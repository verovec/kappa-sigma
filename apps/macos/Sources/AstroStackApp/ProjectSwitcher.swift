package import Foundation
internal import RenderKit
package import SwiftUI

/// The project switcher at the head of the journey sidebar (card 0146).
///
/// The current target and, in a menu, the catalog's other projects by section (open · recent ·
/// in the projects folder), then Open…, New Project…, Welcome Window. Opening another project
/// adds a window (the macOS document model); a project a window already shows comes forward;
/// this window keeps running.
package struct ProjectSwitcher: View {
  /// The closures behind the menu's items, wired by the window.
  package struct Actions {
    /// Opens the project at the URL (adds a window, or brings its window forward).
    package let open: (URL) -> Void
    /// Open…: the Open panel.
    package let choose: () -> Void
    /// New Project…: the welcome window's naming sheet.
    package let newProject: () -> Void
    /// Welcome Window.
    package let welcome: () -> Void

    /// The four closures.
    package init(
      open: @escaping (URL) -> Void, choose: @escaping () -> Void,
      newProject: @escaping () -> Void, welcome: @escaping () -> Void
    ) {
      self.open = open
      self.choose = choose
      self.newProject = newProject
      self.welcome = welcome
    }
  }

  /// Where the switcher's projects come from: the catalog, its reload, the actions — the live
  /// welcome window's, or a stub for a window built in tests (no machine read).
  package struct Source {
    /// The projects listed.
    package let catalog: ProjectCatalog
    let actions: Actions
    let reload: () async -> Void

    package init(catalog: ProjectCatalog, actions: Actions, reload: @escaping () async -> Void) {
      self.catalog = catalog
      self.actions = actions
      self.reload = reload
    }

    /// The welcome window's catalog and its statics: another project opens in its own window.
    package static let live = Self(
      catalog: WelcomeWindow.model.catalog,
      actions: Actions(
        open: { url in Task { await WelcomeWindow.open(url) } },
        choose: { WelcomeWindow.choose() },
        newProject: { WelcomeWindow.showNewProject() },
        welcome: { WelcomeWindow.show() }),
      reload: { await WelcomeWindow.model.reload() })

    /// No project, nothing read, nothing done: a window hosted in a test.
    package static let empty = Self(
      catalog: ProjectCatalog(openProjects: { [] }, recentURLs: { [] }, folderURLs: { [] }),
      actions: Actions(open: { _ in }, choose: {}, newProject: {}, welcome: {}), reload: {})
  }

  /// The menu's projects by section: the catalog's entries (already one per package, first
  /// origin kept), split once.
  package struct Items: Equatable {
    /// The projects a window shows, in document order.
    package let open: [ProjectCatalog.Entry]
    /// The recent projects not open, in AppKit's order.
    package let recent: [ProjectCatalog.Entry]
    /// The rest of the projects folder, by target.
    package let folder: [ProjectCatalog.Entry]

    package static func make(entries: [ProjectCatalog.Entry]) -> Self {
      let byOrigin = Dictionary(grouping: entries, by: \.origin)
      return Self(
        open: byOrigin[.open] ?? [], recent: byOrigin[.recent] ?? [],
        folder: byOrigin[.folder] ?? [])
    }
  }

  let target: String
  let currentKey: String?
  let source: Source
  @Environment(\.controlActiveState) private var activeState
  @Environment(\.locale) private var locale

  /// The switcher of the window whose project has the path key `currentKey` (the model's
  /// `head.key`; `nil`, with an empty `target`, for an untitled project), over `source`.
  package init(target: String, currentKey: String?, source: Source) {
    self.target = target
    self.currentKey = currentKey
    self.source = source
  }

  package var body: some View {
    let items = Items.make(entries: source.catalog.entries)
    Menu {
      section(.app("Open projects"), items.open)
      section(.app("Recent projects"), items.recent)
      section(.app("In the projects folder"), items.folder)
      Divider()
      Button(.app("Open…")) { source.actions.choose() }
        .accessible(.projectSwitcherOpen, label: .app("Open…"))
      Button(.app("New Project…")) { source.actions.newProject() }
        .accessible(.projectSwitcherNew, label: .app("New Project…"))
      Button(.app("Welcome Window")) { source.actions.welcome() }
        .accessible(.projectSwitcherWelcome, label: .app("Welcome Window"))
    } label: {
      HStack(spacing: DesignMetrics.spacingXS) {
        Text(verbatim: name).font(.headline)
        Image(systemName: "chevron.down").font(.caption)
          .foregroundStyle(DesignColor.textSecondary.color)
      }
    }
    .menuStyle(.borderlessButton)
    // The head draws its own chevron.
    .menuIndicator(.hidden)
    .accessible(.projectSwitcher, verbatim: name)
    // Fresh each time this window is (or becomes) key — on appear included; another window
    // closed or opened meanwhile shows at once. The reload drops a stale generation itself.
    .task(id: activeState == .key) {
      if activeState == .key { await source.reload() }
    }
  }

  /// The head's word: the target, or « Projects » for an untitled window.
  private var name: String {
    target.isEmpty ? String(localized: .app("Projects", locale: locale)) : target
  }

  /// One section of projects, absent when empty.
  @ViewBuilder
  private func section(_ title: LocalizedStringResource, _ entries: [ProjectCatalog.Entry])
    -> some View
  {
    if !entries.isEmpty {
      Section {
        ForEach(entries) { entry in
          ProjectSwitcherItem(
            entry: entry, isCurrent: entry.key == currentKey, open: source.actions.open)
        }
      } header: {
        Text(title)
      }
    }
  }
}
