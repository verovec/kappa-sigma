package import Foundation
package import SwiftUI

/// What a pane shows before it has anything: an icon, what is missing, what to do — and, with
/// `help`, the « ? » of the stage beside its title (card 0086).
package struct EmptyState: View {
  private let title: LocalizedStringResource
  private let message: LocalizedStringResource
  private let systemImage: String
  private let help: KeyedHelp?

  /// The empty pane: `title` (« No capture »), `message` (the next step).
  package init(
    _ title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String,
    help: KeyedHelp? = nil
  ) {
    self.title = title
    self.message = message
    self.systemImage = systemImage
    self.help = help
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
    }
  }
}
