internal import RenderKit
package import StackKit
package import SwiftUI

/// What the catalogue knows of one object (card 0130): its names, type, position, size,
/// magnitude and list — read-only, the plate solve offers its position, never sets it (R2).
package struct ObjectCard: View {
  let object: SkyObject
  let close: () -> Void
  @Environment(\.locale) private var locale

  /// The card of `object`; `close` hands the detail column back to the stage.
  package init(object: SkyObject, close: @escaping () -> Void) {
    self.object = object
    self.close = close
  }

  package var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
        HStack(alignment: .firstTextBaseline) {
          SectionHeader(
            .app("\(object.name)"),
            detail: object.commonNames.isEmpty
              ? nil : .app("\(object.commonNames.joined(separator: ", "))"))
          Spacer()
          Button(.app("Close")) { close() }
            .accessible(.objectCardClose, label: .app("Close"))
        }
        Grid(alignment: .leading, horizontalSpacing: DesignMetrics.spacingM) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            GridRow {
              Text(row.label).foregroundStyle(DesignColor.textSecondary.color)
              Text(verbatim: row.value).textSelection(.enabled)
            }
          }
        }
        Text(.app("The plate-solve panel offers this position; nothing is set for you."))
          .font(.caption).foregroundStyle(DesignColor.textSecondary.color)
      }
      .padding(DesignMetrics.spacingL)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// The card's lines, the unknown ones left out.
  private var rows: [(label: LocalizedStringResource, value: String)] {
    let format = AstroFormat(locale: locale)
    var rows: [(label: LocalizedStringResource, value: String)] = []
    if let type = object.type {
      rows.append((.app("Type"), SkyObjectWords.type(type, locale: locale)))
    }
    rows.append((.app("Right ascension"), format.rightAscension(degrees: object.raDeg)))
    rows.append((.app("Declination"), format.declination(degrees: object.decDeg)))
    if let size = SkyObjectWords.size(object, locale: locale) { rows.append((.app("Size"), size)) }
    if let magnitude = SkyObjectWords.magnitude(object, locale: locale) {
      rows.append((.app("Magnitude"), magnitude))
    }
    if !object.aliases.isEmpty {
      rows.append((.app("Also known as"), object.aliases.joined(separator: ", ")))
    }
    rows.append((.app("Catalogue"), SkyObjectWords.source(object.source)))
    return rows
  }
}
