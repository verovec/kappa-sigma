import StackKit
import Testing

/// `SirilScriptTests.testBackgroundExtractionScripts` of card 0072: the rendered `.ssf` for the
/// RBF and polynomial engines carry the legacy strings (`scripts.go:1046` SubskyRBFCmd, SubskyCmd).
@Suite("SirilScript renders the background-extraction scripts with the legacy flags")
struct BackgroundScriptTests {
  @Test(
    "testBackgroundExtractionScripts",
    arguments: [
      (
        BackgroundEngine.sirilRBF(smooth: 0.5, samples: 30, tolerance: 1.5, dither: true),
        "subsky -rbf -smooth=0.5 -samples=30 -tolerance=1.5 -dither"
      ),
      (
        .sirilRBF(smooth: 0.25, samples: 20, tolerance: 1, dither: false),
        "subsky -rbf -smooth=0.25 -samples=20 -tolerance=1"
      ),
      (.sirilPolynomial(degree: 1), "subsky 1"), (.sirilPolynomial(degree: 4), "subsky 4"),
    ])
  func testBackgroundExtractionScripts(engine: BackgroundEngine, subsky: String) throws {
    let command = try #require(engine.sirilSubsky)
    #expect(command.line == subsky && command.verb == "subsky")
    let script = SirilScripts.backgroundExtraction(load: "input", out: "corrected", subsky: command)
    #expect(script.render() == SirilScript.header + "load input\n\(subsky)\nsave corrected\n")
  }

  @Test("GraXpert has no Siril command")
  func testGraXpertHasNoSirilCommand() {
    #expect(BackgroundEngine.graxpert(smoothing: 0.5).sirilSubsky == nil)
    #expect(BackgroundEngine.graxpert(smoothing: 0.5).usesGraXpert)
    #expect(!BackgroundEngine.sirilPolynomial(degree: 1).usesGraXpert)
  }
}
