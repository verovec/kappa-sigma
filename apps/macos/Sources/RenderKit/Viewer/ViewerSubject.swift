package import Foundation

/// What the viewer shows: the image itself, a process's preview of it, or the background model.
///
/// Its histogram says which (card 0128). Display only (R2): no process reads it.
package enum ViewerSubject: Sendable {
  case image
  case preview
  /// The background extraction's model layer (« Show model », card 0072).
  case model
}

extension ViewerModel {
  /// The histogram's header for `locale`: what it counts (`subject`), over the whole image or
  /// the `region`, in which values (`domain`, the domain picker's own word) — « Histogram —
  /// preview · whole image · linear ».
  package nonisolated static func histogramHeader(
    subject: ViewerSubject, region: Bool, domain: HistogramDomain, locale: Locale? = nil
  ) -> String {
    let what: LocalizedStringResource =
      switch subject {
      case .image: .renderKit("image", locale: locale)
      case .preview: .renderKit("preview", locale: locale)
      case .model: .renderKit("background model", locale: locale)
      }
    let over: LocalizedStringResource =
      region ? .renderKit("region", locale: locale) : .renderKit("whole image", locale: locale)
    let values: LocalizedStringResource =
      switch domain {
      case .linear: .renderKit("Linear", locale: locale)
      case .display: .renderKit("Displayed", locale: locale)
      }
    let words = [what, over].map { String(localized: $0) }
    let domainWord = String(localized: values).lowercased(with: locale ?? .current)
    return String(
      localized: .renderKit("Histogram — \(words[0]) · \(words[1]) · \(domainWord)", locale: locale)
    )
  }
}
