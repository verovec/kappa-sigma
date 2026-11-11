internal import Foundation
internal import RenderKit
package import SwiftUI

/// The bucket frames the project keeps on disk (card 0192).
///
/// Their size and folder, and — where it is offered — « Remove Downloaded Frames… », confirmed
/// with what it frees and what it leaves alone. Nothing is removed without that click (R2);
/// nothing while a run is going.
package struct KeptFramesLine: View {
  var model: ProjectWindowModel
  var offersRemoval: Bool
  @Environment(\.locale) private var locale
  @State private var confirming = false

  /// The line of what `model` keeps, with the button when `offersRemoval`.
  package init(model: ProjectWindowModel, offersRemoval: Bool = true) {
    self.model = model
    self.offersRemoval = offersRemoval
  }

  package var body: some View {
    if let kept = model.keptFrames {
      HStack(alignment: .firstTextBaseline) {
        Label {
          Text(Self.notice(kept, locale: locale))
        } icon: {
          Image(systemName: "externaldrive.badge.icloud")
        }
        .foregroundStyle(DesignColor.textSecondary.color)
        Spacer()
        if offersRemoval {
          Button(.app("Remove Downloaded Frames…"), role: .destructive) { confirming = true }
            .disabled(!model.canRemoveKeptFrames)
            .help(Text(.app("Deletes only the copies downloaded from the bucket.")))
            .accessible(.exportRemoveKeptFrames, label: .app("Remove Downloaded Frames…"))
        }
      }
      .confirmationDialog(
        Text(.app("Remove the downloaded frames?")), isPresented: $confirming
      ) {
        Button(.app("Remove"), role: .destructive) { model.removeKeptFrames() }
        Button(.app("Cancel"), role: .cancel) {}
      } message: {
        Text(Self.consequence(kept, locale: locale))
      }
    }
  }

  /// How much is kept, and where.
  package static func notice(_ kept: KeptFrames, locale: Locale) -> LocalizedStringResource {
    let size = AstroFormat(locale: locale).bytes(kept.bytes)
    let path = (kept.folder.path as NSString).abbreviatingWithTildeInPath
    return .app("Downloaded from the bucket: \(size) kept in \(path).", locale: locale)
  }

  /// What removing frees, and what it never touches.
  package static func consequence(_ kept: KeptFrames, locale: Locale) -> LocalizedStringResource {
    let size = AstroFormat(locale: locale).bytes(kept.bytes)
    return .app(
      "Frees \(size). The bucket and this Mac's captures stay; the next run downloads again.",
      locale: locale)
  }
}
