package import Foundation
package import SwiftUI

/// What a pane shows before it has anything: an icon, what is missing, what to do.
package struct EmptyState: View {
  private let title: LocalizedStringResource
  private let message: LocalizedStringResource
  private let systemImage: String

  /// The empty pane: `title` (« No capture »), `message` (the next step).
  package init(
    _ title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String
  ) {
    self.title = title
    self.message = message
    self.systemImage = systemImage
  }

  package var body: some View {
    ContentUnavailableView {
      Label {
        Text(title)
      } icon: {
        Image(systemName: systemImage)
      }
    } description: {
      Text(message)
    }
  }
}
