package import Foundation
package import SwiftUI

/// A verdict: its icon and its words in the status colour — never colour alone.
package struct StatusBadge: View {
  private let status: DesignStatus
  private let text: Text

  /// `status` worded by a catalog resource.
  package init(_ status: DesignStatus, _ words: LocalizedStringResource) {
    self.status = status
    text = Text(words)
  }

  /// `status` worded by text that is already in the user's language (an error's message, a
  /// StackKit note).
  package init(_ status: DesignStatus, verbatim words: String) {
    self.status = status
    text = Text(verbatim: words)
  }

  package var body: some View {
    Label {
      text
    } icon: {
      Image(systemName: status.systemImage)
    }
    .foregroundStyle(status.token.color)
  }
}
