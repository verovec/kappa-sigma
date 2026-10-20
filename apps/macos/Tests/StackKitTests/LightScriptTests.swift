import StackKit
import Testing

/// The light-path builders added by 0048 (`scripts.go:168-250`): ingest by `link` or `convert`,
/// the two-pass registration flag, and `calibrate_single` for a one-frame set.
@Suite("SirilScripts — light ingest, two-pass registration, lone frames")
struct LightScriptTests {
  static let masters = CalibrationMasters(dark: "/m/dark.fits", flat: "/m/flat.fits")

  @Test("FITS is linked; anything else is converted")
  func testIngest() {
    #expect(SirilIngest(paths: ["/a/x.fits", "/a/y.FIT", "/a/z.fts"]) == .link)
    #expect(SirilIngest(paths: ["/a/x.fits", "/a/y.NEF"]) == .convert)
  }

  @Test("convert ingest and two-pass registration, on the calibrated sequence")
  func testCalibrateRegister_convertTwoPass() {
    let script = SirilScripts.calibrateRegister(
      seq: "light", masters: Self.masters, ingest: .convert, twoPass: true)
    #expect(
      script.render().hasSuffix(
        """
        convert light -out=.
        calibrate light -dark=/m/dark.fits -flat=/m/flat.fits -cc=dark -prefix=pp_
        register pp_light -2pass

        """))
    #expect(SirilScripts.calibrated("light", masters: Self.masters) == "pp_light")
    #expect(SirilScripts.calibrated("light", masters: CalibrationMasters()) == "light")
  }

  @Test("a pair rescue pins the reference and relaxes star detection")
  func testAlignPair() {
    #expect(
      SirilScripts.alignPair(seq: "pair").render().hasSuffix(
        """
        link pair -out=.
        setfindstar -sigma=0.5 -roundness=0.42 -relax=on
        setref pair 1
        register pair
        setfindstar reset

        """))
  }

  @Test("a lone frame is calibrated as an image; without masters it is only ingested")
  func testCalibrateSingle() {
    let script = SirilScripts.calibrateSingle(seq: "light", masters: Self.masters)
    #expect(
      script.render().hasSuffix(
        """
        link light -out=.
        calibrate_single light_00001 -dark=/m/dark.fits -flat=/m/flat.fits -cc=dark -prefix=pp_

        """))
    let bare = SirilScripts.calibrateSingle(seq: "light", masters: CalibrationMasters())
    #expect(bare.render().hasSuffix("link light -out=.\n"))
  }
}
