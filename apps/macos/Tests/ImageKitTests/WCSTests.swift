import Foundation
import ImageKit
import Testing

/// An independent TAN deprojection: the tangent-plane point (ξ, η, 1) rotated into the
/// equatorial frame by the east/north/centre basis at (α0, δ0) — vector algebra, not the
/// spherical-trigonometry formulas `WCS` uses (Calabretta & Greisen 2002, §5.1.3 and eq. 2).
enum TangentPlaneOracle {
  static func sky(xi: Double, eta: Double, ra0: Double, dec0: Double) -> (ra: Double, dec: Double) {
    let (alpha, delta) = (ra0 * .pi / 180, dec0 * .pi / 180)
    let east = SIMD3(-sin(alpha), cos(alpha), 0)
    let north = SIMD3(-sin(delta) * cos(alpha), -sin(delta) * sin(alpha), cos(delta))
    let centre = SIMD3(cos(delta) * cos(alpha), cos(delta) * sin(alpha), sin(delta))
    let point = centre + (xi * .pi / 180) * east + (eta * .pi / 180) * north
    var ra = atan2(point.y, point.x) * 180 / .pi
    if ra < 0 { ra += 360 }
    return (ra, atan2(point.z, (point.x * point.x + point.y * point.y).squareRoot()) * 180 / .pi)
  }

  /// Great-circle separation in arcseconds.
  static func separation(
    _ first: (ra: Double, dec: Double), _ second: (ra: Double, dec: Double)
  ) -> Double {
    func unit(_ sky: (ra: Double, dec: Double)) -> SIMD3<Double> {
      let (alpha, delta) = (sky.ra * .pi / 180, sky.dec * .pi / 180)
      return SIMD3(cos(delta) * cos(alpha), cos(delta) * sin(alpha), sin(delta))
    }
    let (one, two) = (unit(first), unit(second))
    let cross = SIMD3(
      one.y * two.z - one.z * two.y, one.z * two.x - one.x * two.z, one.x * two.y - one.y * two.x)
    return atan2((cross * cross).sum().squareRoot(), (one * two).sum()) * 180 / .pi * 3600
  }
}

@Suite("WCS: TAN plate solution from the header, pixel → RA/Dec")
struct WCSTests {
  static func header(_ pairs: [(String, String)]) -> FITSHeader {
    // A header-only FITS stream: parse never reads the (absent) data unit.
    // swiftlint:disable:next force_try
    try! FITSFile.parse(FITSBytes.header(pairs.map { FITSBytes.card($0.0, $0.1) })).header
  }

  /// M31-like solution: 0.98″/px, rotated 37°, flipped in x.
  static let tanCD = header([
    ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"), ("CRPIX1", "3124.5"),
    ("CRPIX2", "2088.5"), ("CRVAL1", "10.6847"), ("CRVAL2", "41.2690"),
    ("CD1_1", "-2.1739E-04"), ("CD1_2", "1.6382E-04"), ("CD2_1", "1.6382E-04"),
    ("CD2_2", "2.1739E-04"),
  ])

  @Test(
    "at CRPIX the solution is CRVAL; elsewhere it matches the tangent-plane oracle within 1″",
    arguments: [(0, 0), (3123, 2087), (6247, 4175), (100, 4000), (5000, 12)])
  func testPixelToSky(x: Int, y: Int) throws {
    let wcs = try #require(WCS(header: Self.tanCD))
    let sky = wcs.sky(x: Double(x), y: Double(y))
    // FITS pixel 1 is array index 0.
    let (dx, dy) = (Double(x) + 1 - 3124.5, Double(y) + 1 - 2088.5)
    let xi = -2.1739E-04 * dx + 1.6382E-04 * dy
    let eta = 1.6382E-04 * dx + 2.1739E-04 * dy
    let oracle = TangentPlaneOracle.sky(xi: xi, eta: eta, ra0: 10.6847, dec0: 41.2690)
    #expect(TangentPlaneOracle.separation((sky.ra, sky.dec), oracle) <= 1)
    #expect((0..<360).contains(sky.ra))
  }

  @Test(
    "TAN-SIP (what Siril's solver writes): the A/B polynomials shift the pixel before CD",
    arguments: [(0, 0), (6247, 4175), (2352, 2440), (40, 4100)])
  func testSIPDistortion(x: Int, y: Int) throws {
    // Run #76 master's solution (PC × CDELT, order-2 SIP), as Siril 1.4 writes it.
    let wcs = try #require(
      WCS(
        header: Self.header([
          ("CTYPE1", "'RA---TAN-SIP'"), ("CTYPE2", "'DEC--TAN-SIP'"), ("CRPIX1", "2353.40893555"),
          ("CRPIX2", "2441.85512288"), ("CRVAL1", "11.2219967839"), ("CRVAL2", "40.6512777227"),
          ("CDELT1", "-0.000865736967894272"), ("CDELT2", "0.000865657528782235"),
          ("PC1_1", "0.130065249061597"), ("PC1_2", "-0.991505436690362"),
          ("PC2_1", "0.991491469849981"), ("PC2_2", "0.130171675931149"),
          ("A_ORDER", "2"), ("A_2_0", "1.3933641702E-07"), ("A_1_1", "-1.47866970311E-07"),
          ("A_0_2", "-3.08206540509E-08"), ("B_ORDER", "2"), ("B_2_0", "-3.35900995798E-08"),
          ("B_1_1", "1.9663640956E-07"), ("B_0_2", "-6.04499789111E-08"),
        ])))
    let (pu, pv) = (Double(x) + 1 - 2353.40893555, Double(y) + 1 - 2441.85512288)
    let du = 1.3933641702E-07 * pu * pu - 1.47866970311E-07 * pu * pv - 3.08206540509E-08 * pv * pv
    let dv = -3.35900995798E-08 * pu * pu + 1.9663640956E-07 * pu * pv - 6.04499789111E-08 * pv * pv
    let (cdelt1, cdelt2) = (-0.000865736967894272, 0.000865657528782235)
    let xi = cdelt1 * (0.130065249061597 * (pu + du) - 0.991505436690362 * (pv + dv))
    let eta = cdelt2 * (0.991491469849981 * (pu + du) + 0.130171675931149 * (pv + dv))
    let oracle = TangentPlaneOracle.sky(xi: xi, eta: eta, ra0: 11.2219967839, dec0: 40.6512777227)
    let sky = wcs.sky(x: Double(x), y: Double(y))
    #expect(TangentPlaneOracle.separation((sky.ra, sky.dec), oracle) <= 1)
  }

  @Test("CDELT + CROTA2 gives the same solution as the equivalent CD matrix")
  func testCDELTCROTA() throws {
    let rho = 37.0 * .pi / 180
    let (c1, c2) = (-2.7222E-04, 2.7222E-04)
    let legacy = Self.header([
      ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"), ("CRPIX1", "100"), ("CRPIX2", "80"),
      ("CRVAL1", "350.2"), ("CRVAL2", "-12.5"), ("CDELT1", "\(c1)"), ("CDELT2", "\(c2)"),
      ("CROTA2", "37.0"),
    ])
    let matrix = Self.header([
      ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"), ("CRPIX1", "100"), ("CRPIX2", "80"),
      ("CRVAL1", "350.2"), ("CRVAL2", "-12.5"), ("CD1_1", "\(c1 * cos(rho))"),
      ("CD1_2", "\(-c2 * sin(rho))"), ("CD2_1", "\(c1 * sin(rho))"), ("CD2_2", "\(c2 * cos(rho))"),
    ])
    let fromCROTA = try #require(WCS(header: legacy))
    let fromCD = try #require(WCS(header: matrix))
    for (x, y) in [(0.0, 0.0), (199.0, 159.0), (99.0, 79.0)] {
      let (one, two) = (fromCROTA.sky(x: x, y: y), fromCD.sky(x: x, y: y))
      #expect(TangentPlaneOracle.separation((one.ra, one.dec), (two.ra, two.dec)) <= 1e-6)
    }
  }

  @Test(
    "no solution without TAN projection cards or a scale",
    arguments: [
      [("CRPIX1", "1"), ("CRPIX2", "1"), ("CRVAL1", "0"), ("CRVAL2", "0")],
      [
        ("CTYPE1", "'RA---SIN'"), ("CTYPE2", "'DEC--SIN'"), ("CRPIX1", "1"), ("CRPIX2", "1"),
        ("CRVAL1", "0"), ("CRVAL2", "0"), ("CDELT1", "1"), ("CDELT2", "1"),
      ],
      [
        ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"), ("CRPIX1", "1"), ("CRPIX2", "1"),
        ("CRVAL1", "0"), ("CRVAL2", "0"),
      ],
    ])
  func testMissingSolution(cards: [(String, String)]) {
    #expect(WCS(header: Self.header(cards)) == nil)
  }

  @Test("missing CDi_j default to 0 and missing PCi_j to the identity (FITS WCS paper I)")
  func testMatrixCardDefaults() throws {
    let base = [
      ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"), ("CRPIX1", "50"), ("CRPIX2", "50"),
      ("CRVAL1", "120"), ("CRVAL2", "30"),
    ]
    // A 90° rotation written with the off-diagonal CD cards only.
    let offDiagonal = try #require(
      WCS(header: Self.header(base + [("CD1_2", "-1.0E-03"), ("CD2_1", "1.0E-03")])))
    #expect(offDiagonal.cd == SIMD4(0, -1.0E-03, 1.0E-03, 0))
    // A PC matrix without PC1_1 (= 1), with a CROTA2 that must not be used.
    let partialPC = try #require(
      WCS(
        header: Self.header(
          base + [
            ("CDELT1", "-2.0E-03"), ("CDELT2", "2.0E-03"), ("PC2_2", "0.5"), ("CROTA2", "40"),
          ])))
    #expect(partialPC.cd == SIMD4(-2.0E-03, 0, 0, 1.0E-03))
  }

  @Test("the metadata carries the header's solution")
  func testMetadataCarriesWCS() {
    #expect(ImageMetadata(header: Self.tanCD).wcs == WCS(header: Self.tanCD))
    #expect(ImageMetadata(header: Self.header([])).wcs == nil)
  }
}
