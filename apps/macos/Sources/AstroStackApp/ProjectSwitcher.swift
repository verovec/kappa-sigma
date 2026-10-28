internal import Combine
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
    package static var live: Self {
      Self(
        catalog: WelcomeWindow.model.catalog,
        actions: Actions(
          open: { url in Task { await WelcomeWindow.open(url) } },
          choose: { WelcomeWindow.choose() },
          newProject: { WelcomeWindow.showNewProject() },
          welcome: { WelcomeWindow.show() }),
        reload: { await WelcomeWindow.model.reload() })
    }

    /// No project, nothing read, nothing done: a window hosted in a test.
    package static var empty: Self {
      Self(
        catalog: ProjectCatalog(openProjects: { [] }, recentURLs: { [] }, folderURLs: { [] }),
        actions: Actions(open: { _ in }, choose: {}, newProject: {}, welcome: {}), reload: {})
    }
  }

  /// The menu's projects, by section, from the catalog's entries.
  package struct Items: Equatable {
    package struct Project: Equatable, Identifiable {
      package let url: URL
      package let target: String
      package let key: String
      /// The project this window shows: checked, chosen again it only comes forward.
      package let isCurrent: Bool
      package var id: URL { url }
    }

    package let open: [Project]
    package let recent: [Project]
    package let folder: [Project]

    /// A partition of the catalog's entries (already one per package, first origin kept) by
    /// section, the one at `current` checked.
    package static func make(entries: [ProjectCatalog.Entry], current: URL?) -> Self {
      let currentKey = current.map(WelcomeModel.key)
      let projects = entries.map { entry in
        Project(
          url: entry.url, target: entry.target, key: entry.key,
          isCurrent: entry.key == currentKey)
      }
      let origins = entries.map(\.origin)
      func section(_ origin: ProjectCatalog.Origin) -> [Project] {
        zip(projects, origins).filter { $1 == origin }.map(\.0)
      }
      return Self(open: section(.open), recent: section(.recent), folder: section(.folder))
    }
  }

  let target: String
  let current: URL?
  let source: Source

  /// The switcher of the window showing `current` (`nil` for an untitled project), named
  /// `target` (empty for an untitled one), over `source`.
  package init(target: String, current: URL?, source: Source) {
    self.target = target
    self.current = current
    self.source = source
  }

  package var body: some View {
    let items = Items.make(entries: source.catalog.entries, current: current)
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
        if target.isEmpty {
          Text(.app("Projects")).font(.headline)
        } else {
          Text(verbatim: target).font(.headline)
        }
        Image(systemName: "chevron.down").font(.caption)
          .foregroundStyle(DesignColor.textSecondary.color)
      }
    }
    .menuStyle(.borderlessButton)
    .accessible(.projectSwitcher, label: .app("Projects"))
    // Fresh when the window appears and whenever it becomes key again (another window closed
    // or opened meanwhile); the reload drops a stale generation itself.
    .task { await source.reload() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      Task { await source.reload() }
    }
  }

  /// One section of projects, absent when empty.
  @ViewBuilder
  private func section(_ title: LocalizedStringResource, _ projects: [Items.Project]) -> some View {
    if !projects.isEmpty {
      Section {
        ForEach(projects) { project in
          Button {
            source.actions.open(project.url)
          } label: {
            if project.isCurrent {
              Label {
                Text(verbatim: project.target)
              } icon: {
                Image(systemName: "checkmark")
              }
            } else {
              Text(verbatim: project.target)
            }
          }
          .accessible(.projectSwitcherProject(project.key), verbatim: project.target)
        }
      } header: {
        Text(title)
      }
    }
  }
}
