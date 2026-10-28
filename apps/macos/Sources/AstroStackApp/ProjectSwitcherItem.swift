package import SwiftUI

/// One project of the switcher's menu (card 0146): its target, checked when it is the project
/// this window shows (chosen again it only comes forward).
package struct ProjectSwitcherItem: View {
  let entry: ProjectCatalog.Entry
  let isCurrent: Bool
  let open: (URL) -> Void

  /// The item for `entry`; `open` is the switcher's action.
  package init(entry: ProjectCatalog.Entry, isCurrent: Bool, open: @escaping (URL) -> Void) {
    self.entry = entry
    self.isCurrent = isCurrent
    self.open = open
  }

  package var body: some View {
    Button {
      open(entry.url)
    } label: {
      if isCurrent {
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
}
