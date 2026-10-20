import SwiftUI

/// The content of a project window.
///
/// Empty until the import and Studio cards fill it.
struct ProjectWindowView: View {
  var body: some View {
    ContentUnavailableView(
      "Empty project", systemImage: "sparkles",
      description: Text("Captures, stacks and images will appear here.")
    )
    .frame(minWidth: 640, minHeight: 400)
  }
}
