package import AppKit
internal import ProjectKit

/// Fills File › Open Recent each time it opens (card 0144): AppKit's recent documents still on
/// disk, most recent first, titled by their target, the open ones checked.
///
/// One source of recents, AppKit's (`NSDocumentController.recentDocumentURLs`, noted on every
/// open, card 0077); « Clear Menu » below the separator is the catalog's `file.clearRecent`, sent
/// to `AppDelegate.clearRecentProjects` (an item sending `clearRecentDocuments:` would make AppKit
/// fill this menu itself). A
/// project opens like a recent one in the welcome window: an open one only comes forward.
package final class RecentProjectsMenu: NSObject, NSMenuDelegate {
  /// The app's: AppKit's recents, the projects open in a document, `WelcomeWindow.open`.
  package static let live = RecentProjectsMenu(
    recentURLs: WelcomeWindow.recentURLs,
    openKeys: WelcomeWindow.openProjectKeys,
    open: { url in Task { await WelcomeWindow.open(url) } })

  private let recentURLs: @MainActor () -> [URL]
  private let openKeys: @MainActor () -> Set<String>
  private let open: @MainActor (URL) -> Void

  /// A menu listing `recentURLs`, checking those `openKeys` names (`WelcomeModel.key`), and
  /// handing an activated one to `open`.
  package init(
    recentURLs: @escaping @MainActor () -> [URL],
    openKeys: @escaping @MainActor () -> Set<String>,
    open: @escaping @MainActor (URL) -> Void
  ) {
    self.recentURLs = recentURLs
    self.openKeys = openKeys
    self.open = open
  }

  /// Rebuilds the project items above the separator; the separator hides with no project.
  package func menuNeedsUpdate(_ menu: NSMenu) {
    while let first = menu.items.first, !first.isSeparatorItem { menu.removeItem(first) }
    let open = openKeys()
    let projects = WelcomeModel.onDisk(recentURLs())
    for (index, url) in projects.enumerated() {
      let item = NSMenuItem(
        title: ProjectPackage.target(of: url), action: #selector(openProject(_:)),
        keyEquivalent: "")
      item.target = self
      item.representedObject = url
      // Two targets can share a name in different folders: the path tells them apart.
      item.toolTip = url.path
      item.state = open.contains(WelcomeModel.key(url)) ? .on : .off
      menu.insertItem(item, at: index)
    }
    menu.items.first(where: \.isSeparatorItem)?.isHidden = projects.isEmpty
  }

  /// A project item: opens its package.
  @objc private func openProject(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    open(url)
  }
}
