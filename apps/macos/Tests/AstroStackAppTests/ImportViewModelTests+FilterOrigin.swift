import AstroStackApp
import Foundation
import StackKit
import Testing

/// Card 0163: each light filter row shows the verdict and where it came from, next to the picker;
/// a mapping still wins and says what it replaced.
extension ImportViewModelTests {
  /// A light set of `filter` whose frame was named by `origin`.
  nonisolated static func light(_ filter: String, _ origin: FilterOrigin?) -> FrameSet {
    var frame = FakePlanner.frame(SetKey(type: .light, filter: filter))
    frame.filter = filter
    frame.filterOrigin = origin
    return FrameSet(
      key: SetKey(type: .light, object: "M 31", filter: filter, exposureMs: 300_000),
      frames: [frame], indices: [0])
  }

  /// A model whose scan holds Hα from the FITS card and [OIII] from its folder; a mapping of
  /// [OIII] relabels that set as the real scan does.
  static func originModel() async -> ImportViewModel {
    let model = ImportViewModel(planning: { request in
      var inventory = Inventory(root: request.paths.first ?? "", frames: [])
      var oiii = Self.light("OIII", FilterOrigin(source: .folder, raw: "OIII_6.5nm"))
      if let target = request.filterMap["OIII"] {
        oiii = Self.light(target, FilterOrigin(source: .manual, raw: "OIII"))
      }
      inventory.sets = [
        Self.light("Ha", FilterOrigin(source: .header, raw: "H-alpha 7nm")), oiii,
      ]
      return ImportPlan(inventory: inventory, library: [], request: request)
    })
    model.choose(folder: URL(fileURLWithPath: "/c/M31"))
    await model.settled()
    return model
  }

  static func text(_ model: ImportViewModel, _ filter: String, _ language: String) -> String? {
    let lines = model.originWords(of: filter, locale: Locale(identifier: language)).map {
      String(localized: $0)
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  @Test("testFilterOrigin_RowText: the verdict and its source, in English and French")
  func testFilterOriginRowText() async {
    let model = await Self.originModel()
    #expect(model.detected("Ha")?.origins == [FilterOrigin(source: .header, raw: "H-alpha 7nm")])
    #expect(Self.text(model, "Ha", "en") == "Ha — FITS FILTER « H-alpha 7nm »")
    #expect(Self.text(model, "Ha", "fr") == "Ha — FILTER du FITS « H-alpha 7nm »")
    #expect(Self.text(model, "OIII", "en") == "OIII — folder « OIII_6.5nm »")
    #expect(Self.text(model, "OIII", "fr") == "OIII — dossier « OIII_6.5nm »")
    #expect(Self.text(model, "SII", "en") == nil, "no such row")
  }

  @Test("testFilterOrigin_MappingWins: a mapped row names the mapping and its target")
  func testFilterOriginMappingWins() async {
    let model = await Self.originModel()
    model.mapFilter("OIII", to: "SII")
    await model.settled()
    #expect(model.lightFilters == ["Ha", "OIII"])
    #expect(model.detected("OIII")?.verdict == "SII")
    #expect(Self.text(model, "OIII", "en") == "SII — your mapping of « OIII »")
    #expect(Self.text(model, "OIII", "fr") == "SII — votre correspondance de « OIII »")
  }

  @Test(
    "testFilterOrigin_EverySource: each source has its words in both languages",
    arguments: FilterOrigin.Source.allCases)
  func testFilterOriginEverySource(source: FilterOrigin.Source) {
    let origin = FilterOrigin(source: source, raw: "x")
    var seen: Set<String> = []
    for language in ["en", "fr"] {
      let words = String(
        localized: ImportViewModel.originWords(
          verdict: "Ha", origin: origin, locale: Locale(identifier: language)))
      #expect(words.hasPrefix("Ha — "), "\(source) \(language): \(words)")
      #expect(!words.contains("%"), "\(source) \(language): \(words)")
      seen.insert(words)
    }
    #expect(seen.count == 2, "\(source): French differs from English")
  }

  @Test("testFilterOrigin_SeveralSources: a row spanning two nights lists each origin once")
  func testFilterOriginSeveralSources() async {
    let model = ImportViewModel(planning: { request in
      var inventory = Inventory(root: "", frames: [])
      var second = Self.light("Ha", FilterOrigin(source: .folder, raw: "Ha_300s"))
      second.key.session = "2026-10-18"
      second.frames.append(second.frames[0])
      inventory.sets = [Self.light("Ha", FilterOrigin(source: .header, raw: "Ha")), second]
      return ImportPlan(inventory: inventory, library: [], request: request)
    })
    model.choose(folder: URL(fileURLWithPath: "/c/M31"))
    await model.settled()
    #expect(model.lightFilters == ["Ha"])
    #expect(Self.text(model, "Ha", "en") == "Ha — FITS FILTER « Ha »\nHa — folder « Ha_300s »")
  }
}
