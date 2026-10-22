import AstroStackApp
import Foundation
import ProcessKit
import StackKit
import Testing

/// Card 0093: the panel's values as Siril's request — never completed behind the user's back.
@Suite("PlateSolveTool: the request the panel's values make")
struct PlateSolveToolTests {
  static func params(
    ra: String, dec: String, focal: Double = 250, pixel: Double = 3.76, limit: Double = 0,
    catalogue: String = "local-gaia"
  ) throws -> ParamSet {
    var params = ParamSet(schema: PlateSolveProcess.schema)
    try params.set("ra", .text(ra))
    try params.set("dec", .text(dec))
    try params.set("focalMm", .number(focal))
    try params.set("pixelSizeUm", .number(pixel))
    try params.set("limitMag", .number(limit))
    try params.set("catalogue", .choice(catalogue))
    return params
  }

  @Test(
    "refusals, by what is missing or unreadable",
    arguments: [
      ("", "+41 16 09", 250.0, 3.76, PlateSolveTool.InputError.coordinatesMissing),
      ("00 42 44", "", 250, 3.76, .coordinatesMissing),
      ("north", "+41 16 09", 250, 3.76, .unreadable("north")),
      ("00 42 44", "+95 00 00", 250, 3.76, .unreadable("+95 00 00")),
      ("25 00 00", "+41", 250, 3.76, .unreadable("25 00 00")),
      ("00 42 44", "+41 16 09", 0, 3.76, .opticsMissing),
      ("00 42 44", "+41 16 09", 250, 0, .opticsMissing),
    ])
  func testRefusals(
    ra: String, dec: String, focal: Double, pixel: Double, error: PlateSolveTool.InputError
  ) throws {
    let params = try Self.params(ra: ra, dec: dec, focal: focal, pixel: pixel)
    #expect(throws: error) { try PlateSolveTool.request(params) }
  }

  @Test("sexagesimal or degrees, the limit and the catalogue as given")
  func testRequests() throws {
    let local = try PlateSolveTool.request(Self.params(ra: "00 42 44", dec: "+41 16 09"))
    #expect(abs(local.raDegrees - 10.68333) < 1e-5 && abs(local.decDegrees - 41.26917) < 1e-5)
    #expect(local.limitMag == nil && local.catalogue == .localGaia)
    let online = try PlateSolveTool.request(
      Self.params(ra: " 83.8\n", dec: "-5.4 ", limit: 15, catalogue: "online-gaia"))
    #expect(online.raDegrees == 83.8 && online.decDegrees == -5.4)
    #expect(online.limitMag == 15 && online.catalogue == .online)
  }

  @Test("the report says the solution in the view's language")
  func testReport() throws {
    let lines = [
      "Up is +258.45 deg CounterclockWise wrt. N", "Resolution:      3.117 arcsec/px",
      "Image center: alpha: 00 42 48.778, delta: +41 16 17.054",
      "Fetched 1336 stars from Gaia DR3 astrometry catalogue",
    ]
    let solution = try #require(PlateSolution(lines: lines))
    let english = String(
      localized: PlateSolveTool.report(solution, locale: Locale(identifier: "en")))
    let french = String(
      localized: PlateSolveTool.report(solution, locale: Locale(identifier: "fr")))
    #expect(english.hasPrefix("Solved: centre") && english.contains("3.117″/px"))
    #expect(french.contains("3,117″/px") && !french.hasPrefix("Solved"))
  }
}
