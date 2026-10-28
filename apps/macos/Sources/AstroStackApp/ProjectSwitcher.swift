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
    package let open: (URL) -> Void
    package let choose: () -> Void
    package let newProject: () -> Void
    package let welcome: () -> Void

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
    let catalog: ProjectCatalog
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

  /// The menu's projects by section — the catalog's entries (already one per package, first
  /// origin kept) — and the key of the project this window shows.
  package struct Items: Equatable {
    package let open: [ProjectCatalog.Entry]
    package let recent: [ProjectCatalog.Entry]
    package let folder: [ProjectCatalog.Entry]
    package let currentKey: String?

    package static func make(entries: [ProjectCatalog.Entry], currentKey: String?) -> Self {
      Self(
        open: entries.filter { $0.origin == .open },
        recent: entries.filter { $0.origin == .recent },
        folder: entries.filter { $0.origin == .folder }, currentKey: currentKey)
    }

    /// The project this window shows: checked, chosen again it only comes forward.
    package func isCurrent(_ entry: ProjectCatalog.Entry) -> Bool { entry.key == currentKey }
  }

  let target: String
  let currentKey: String?
  let source: Source
  @Environment(\.controlActiveState) private var activeState
  @Environment(\.locale) private var locale

  /// The switcher of the window showing `current`, named `target`, over `source`.
  ///
  /// `current` is `nil` and `target` empty for an untitled project; the current project's key is
  /// resolved here, once.
  package init(target: String, current: URL?, source: Source) {
    self.target = target
    currentKey = current.map(WelcomeModel.key)
    self.source = source
  }

  package var body: some View {
    let items = Items.make(entries: source.catalog.entries, currentKey: currentKey)
    Menu {
      section(.app("Open projects"), items.open, items)
      section(.app("Recent projects"), items.recent, items)
      section(.app("In the projects folder"), items.folder, items)
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
    .accessible(.projectSwitcher, verbatim: name)
    // Fresh when the window appears and each time it becomes key again (another window closed
    // or opened meanwhile); the reload drops a stale generation itself.
    .task { await source.reload() }
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
  private func section(
    _ title: LocalizedStringResource, _ entries: [ProjectCatalog.Entry], _ items: Items
  ) -> some View {
    if !entries.isEmpty {
      Section {
        ForEach(entries) { entry in
          Button {
            source.actions.open(entry.url)
          } label: {
            if items.isCurrent(entry) {
              Label {
                Text(verbatim: entry.target)
              } icon: {
                Image(systemName: "checkmark")
              }
            } else {
              Text(verbatim: entry.target)
            }
          }
          .accessible(.projectSwitcherProject(entry.key), verbatim: entry.target)
        }
      } header: {
        Text(title)
      }
    }
  }
}
