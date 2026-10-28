package import Foundation
internal import ProjectKit
internal import RenderKit
package import SwiftUI

/// The projects of a `ProjectCatalog` in two sections (card 0145): the open and recent ones, then
/// the rest of the projects folder, its path shown once (a click reveals it in the Finder).
package struct ProjectListSection: View {
  private let catalog: ProjectCatalog
  private let folder: URL
  private let open: (URL) -> Void

  /// The list of `catalog`, `folder` being the projects folder; a row click calls `open`.
  package init(catalog: ProjectCatalog, folder: URL, open: @escaping (URL) -> Void) {
    self.catalog = catalog
    self.folder = folder
    self.open = open
  }

  package var body: some View {
    let recent = catalog.entries.filter { $0.origin != .folder }
    let inFolder = catalog.entries.filter { $0.origin == .folder }
    // « No recent project » only when nothing is listed: folder projects are projects too.
    if !recent.isEmpty || inFolder.isEmpty {
      SectionHeader(.app("Recent projects"))
    }
    if catalog.entries.isEmpty {
      Text(.app("No recent project")).foregroundStyle(DesignColor.textSecondary.color)
    }
    ForEach(recent, content: row)
    if !inFolder.isEmpty {
      SectionHeader(.app("In the projects folder"))
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
      } label: {
        Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath)
          .font(DesignMetrics.captionFont).foregroundStyle(DesignColor.textSecondary.color)
      }
      .buttonStyle(.link)
      .accessible(.welcomeFolder, label: .app("Show the projects folder in the Finder"))
      ForEach(inFolder, content: row)
    }
  }

  private func row(_ project: ProjectCatalog.Entry) -> some View {
    Button {
      open(project.url)
    } label: {
      HStack {
        Text(verbatim: project.target).font(.headline)
        Spacer()
        // An open project still opening has no counts yet: nothing is said, it is no error.
        if project.summary != nil || project.origin != .open {
          Text(WelcomeView.counts(project.summary))
            .font(DesignMetrics.captionFont).foregroundStyle(DesignColor.textSecondary.color)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessible(.welcomeProject(WelcomeModel.key(project.url)), verbatim: project.target)
  }
}
