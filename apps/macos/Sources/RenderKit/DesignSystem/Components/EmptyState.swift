package import Foundation
package import SwiftUI

/// What a pane shows before it has anything: an icon, what is missing, what to do — with the
/// stage's « ? » beside its title (`help`, card 0086) and, with `actions`, the one thing to do.
package struct EmptyState<Actions: View>: View {
  private let title: LocalizedStringResource
  private let message: LocalizedStringResource
  private let systemImage: String
  private let help: KeyedHelp?
  private let actions: () -> Actions

  /// The empty pane: `title` (« No capture »), `message` (the next step), `actions` under it.
  package init(
    _ title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String,
    help: KeyedHelp? = nil, @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.title = title
    self.message = message
    self.systemImage = systemImage
    self.help = help
    self.actions = actions
  }

  package var body: some View {
    ContentUnavailableView {
      Label {
        HStack(spacing: DesignMetrics.spacingS) {
          Text(title)
          if let help { help.button }
        }
      } icon: {
        Image(systemName: systemImage)
      }
    } description: {
      Text(message)
    } actions: {
      actions()
    }
  }
}

extension EmptyState where Actions == EmptyView {
  /// The empty pane with nothing to do yet.
  package init(
    _ title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String,
    help: KeyedHelp? = nil
  ) {
    self.init(title, message: message, systemImage: systemImage, help: help) { EmptyView() }
  }
}
