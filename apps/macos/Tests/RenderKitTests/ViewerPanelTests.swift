import Foundation
import RenderKit
import Testing

/// The viewer's histogram says which image it counts (card 0128): what is on screen (the image or
/// a process's preview), over what (the whole image or the region), in which values (linear or
/// displayed).
@MainActor
@Suite("ViewerPanel — the histogram's header names its subject, region and domain")
struct ViewerPanelTests {
  struct Header: Sendable, CustomTestStringConvertible {
    let subject: ViewerSubject
    let region: Bool
    let domain: HistogramDomain
    let en: String
    let fr: String
    var testDescription: String { en }
  }

  nonisolated static let headers: [Header] = [
    Header(
      subject: .image, region: false, domain: .linear,
      en: "Histogram — image · whole image · linear",
      fr: "Histogramme — image · image entière · linéaire"),
    Header(
      subject: .image, region: false, domain: .display,
      en: "Histogram — image · whole image · displayed",
      fr: "Histogramme — image · image entière · affiché"),
    Header(
      subject: .image, region: true, domain: .linear,
      en: "Histogram — image · region · linear",
      fr: "Histogramme — image · région · linéaire"),
    Header(
      subject: .image, region: true, domain: .display,
      en: "Histogram — image · region · displayed",
      fr: "Histogramme — image · région · affiché"),
    Header(
      subject: .preview, region: false, domain: .linear,
      en: "Histogram — preview · whole image · linear",
      fr: "Histogramme — aperçu · image entière · linéaire"),
    Header(
      subject: .preview, region: false, domain: .display,
      en: "Histogram — preview · whole image · displayed",
      fr: "Histogramme — aperçu · image entière · affiché"),
    Header(
      subject: .preview, region: true, domain: .linear,
      en: "Histogram — preview · region · linear",
      fr: "Histogramme — aperçu · région · linéaire"),
    Header(
      subject: .preview, region: true, domain: .display,
      en: "Histogram — preview · region · displayed",
      fr: "Histogramme — aperçu · région · affiché"),
    Header(
      subject: .model, region: false, domain: .linear,
      en: "Histogram — background model · whole image · linear",
      fr: "Histogramme — modèle de fond · image entière · linéaire"),
    Header(
      subject: .model, region: true, domain: .linear,
      en: "Histogram — background model · region · linear",
      fr: "Histogramme — modèle de fond · région · linéaire"),
  ]

  @Test("subject × region × domain, worded in en and fr", arguments: headers)
  func testViewerPanel_histogramHeader_subjectRegionDomain(_ row: Header) {
    for (language, expected) in [("en", row.en), ("fr", row.fr)] {
      let header = ViewerModel.histogramHeader(
        subject: row.subject, region: row.region, domain: row.domain,
        locale: Locale(identifier: language))
      #expect(header == expected, "\(language)")
    }
  }

  @Test("a new viewer counts the image; the subject is display only")
  func testViewerModel_subject_defaultsToImage() throws {
    let model = try ViewerModelTests.model()
    #expect(model.subject == .image)
    let frame = model.frame
    model.subject = .preview
    #expect(model.frame == frame, "the subject changes no pixel and no stretch (R2)")
  }
}
