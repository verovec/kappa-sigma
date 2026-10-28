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
  /// What the menu can do; each a closure the window wires to `WelcomeWindow`.
  package enum Choice: Equatable {
    case project(URL)
    case open
    case newProject
    case welcome
  }

  /// The closures behind the menu's items.
  package struct Actions {
    let open: (URL) -> Void
    let choose: () -> Void
    let newProject: () -> Void
    let welcome: () -> Void

    package init(
      open: @escaping (URL) -> Void, choose: @escaping () -> Void,
      newProject: @escaping () -> Void, welcome: @escaping () -> Void
    ) {
      self.open = open
      self.choose = choose
      self.newProject = newProject
      self.welcome = welcome
    }

    /// Runs the one closure `choice` names.
    package func perform(_ choice: Choice) {
      switch choice {
      case .project(let url): open(url)
      case .open: choose()
      case .newProject: newProject()
      case .welcome: welcome()
      }
    }
  }

  /// The menu's projects, by section, from the catalog's entries.
  package struct Items: Equatable {
    package struct Project: Equatable, Identifiable {
      package let url: URL
      package let target: String
      /// The project this window shows: checked, chosen again it only comes forward.
      package let isCurrent: Bool
      package var id: URL { url }
    }

    package let open: [Project]
    package let recent: [Project]
    package let folder: [Project]

    /// Sections in catalog order; a project found in several places keeps its first section
    /// (the catalog already says so, the menu never lists a package twice).
    package static func make(entries: [ProjectCatalog.Entry], current: URL?) -> Self {
      let currentKey = current.map(WelcomeModel.key)
      var seen = Set<String>()
      var open: [Project] = []
      var recent: [Project] = []
      var folder: [Project] = []
      for entry in entries {
        let key = WelcomeModel.key(entry.url)
        guard seen.insert(key).inserted else { continue }
        let project = Project(url: entry.url, target: entry.target, isCurrent: key == currentKey)
        switch entry.origin {
        case .open: open.append(project)
        case .recent: recent.append(project)
        case .folder: folder.append(project)
        }
      }
      return Self(open: open, recent: recent, folder: folder)
    }
  }

  let target: String
  let catalog: ProjectCatalog
  let current: URL?
  let actions: Actions
  let reload: () async -> Void

  /// The switcher of the window showing `current` (`nil` for an untitled project), named
  /// `target`, over the live `catalog` (reloaded when the switcher appears).
  package init(
    target: String, catalog: ProjectCatalog, current: URL?, actions: Actions,
    reload: @escaping () async -> Void
  ) {
    self.target = target
    self.catalog = catalog
    self.current = current
    self.actions = actions
    self.reload = reload
  }

  package var body: some View {
    let items = Items.make(entries: catalog.entries, current: current)
    Menu {
      section(.app("Open projects"), items.open)
      section(.app("Recent projects"), items.recent)
      section(.app("In the projects folder"), items.folder)
      Divider()
      Button(.app("Open…")) { actions.perform(.open) }
        .accessible(.projectSwitcherOpen, label: .app("Open…"))
      Button(.app("New Project…")) { actions.perform(.newProject) }
        .accessible(.projectSwitcherNew, label: .app("New Project…"))
      Button(.app("Welcome Window")) { actions.perform(.welcome) }
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
    .task { await reload() }
  }

  /// One section of projects, absent when empty.
  @ViewBuilder
  private func section(_ title: LocalizedStringResource, _ projects: [Items.Project]) -> some View {
    if !projects.isEmpty {
      Section {
        ForEach(projects) { project in
          Button {
            actions.perform(.project(project.url))
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
          .accessible(
            .projectSwitcherProject(WelcomeModel.key(project.url)), verbatim: project.target)
        }
      } header: {
        Text(title)
      }
    }
  }
}
