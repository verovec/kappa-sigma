internal import Foundation
internal import RenderKit
internal import SwiftUI

/// The scratch line of the Stacking stage (card 0098): what the next run needs where, the room
/// left there, and what to do when it does not fit — shown, never decided for the user (R2).
struct ScratchBudgetLine: View {
  let budget: ScratchBudget

  var body: some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: budget.fits ? "internaldrive" : "exclamationmark.triangle")
    }
    .foregroundStyle(
      budget.fits ? DesignColor.textSecondary.color : DesignColor.statusError.color
    )
    .padding([.horizontal, .bottom], DesignMetrics.spacingM)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var text: LocalizedStringResource {
    let need = ScratchBudget.gigabytesUp(budget.neededBytes)
    let path = (budget.folder.path as NSString).abbreviatingWithTildeInPath
    guard let room = budget.roomBytes.map(ScratchBudget.gigabytesDown) else {
      return .app("Needs ~\(need) GB of scratch in \(path).")
    }
    guard budget.fits else {
      return .app(
        "Too little scratch: ~\(need) GB in \(path), \(room) GB free (Settings › Scratch folder)."
      )
    }
    return .app("Needs ~\(need) GB of scratch in \(path), \(room) GB free.")
  }
}
