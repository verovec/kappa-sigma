import AstroStackApp
import Foundation
import StackKit
import Testing

/// Every Siril and import error reads as a sentence naming what to act on, in both languages.
@Suite("UserFacingError — one catalog sentence per Siril and import error")
struct UserFacingErrorTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let error: any Error & Sendable
    /// What the sentence must name, in every language.
    let names: String
    let english: String
    var testDescription: String { english }
  }

  nonisolated static let cases: [Case] = [
    Case(
      error: SirilError.notInstalled(path: "/opt/siril-cli"), names: "/opt/siril-cli",
      english:
        "Siril is not installed at /opt/siril-cli. Install Siril 1.4 or later, then try again."),
    Case(
      error: SirilError.notSiril(output: "GIMP 3.2"), names: "GIMP 3.2",
      english: "The program at the Siril path is not Siril (it answered: GIMP 3.2)."),
    Case(
      error: SirilError.unreadableVersion(output: "siril"), names: "siril",
      english: "Siril did not report its version (it answered: siril)."),
    Case(
      error: SirilError.tooOld(version: "1.2.6"), names: "1.2.6",
      english: "Siril 1.2.6 is too old: AstroStack needs Siril 1.4 or later."),
    Case(
      error: SirilError.scriptFailed(exitCode: 3, hint: "no file"), names: "no file",
      english: "A Siril script failed (exit code 3): no file"),
    Case(
      error: SirilError.commandFailed(command: "stack r_pp_light", hint: "out of memory"),
      names: "stack r_pp_light", english: "Siril refused “stack r_pp_light”: out of memory"),
    Case(
      error: SirilError.restarted(command: "register"), names: "register",
      english: "Siril stopped during “register” and was restarted; run the step again."),
    Case(
      error: SirilError.sessionFailed(reason: "pipe busy"), names: "pipe busy",
      english: "Siril could not start: pipe busy"),
    Case(
      error: InspectError.unknownFilterSet("uhc"), names: "uhc",
      english: "“uhc” is not a filter set: use unknown, broadband or dualband."),
    Case(
      error: InspectError.unknownColorChoice("rgb"), names: "rgb",
      english: "“rgb” is not a colour model: use auto, mono or osc."),
    Case(
      error: InspectError.noLightsForColorModel(choice: "mono", dropped: 36), names: "36",
      english: "No light frame matches the colour model mono (36 dropped): choose another."),
    Case(
      error: InspectError.unreadableFolder("/c/M31-DB"), names: "/c/M31-DB",
      english: "The folder /c/M31-DB cannot be read: "
        + "check that it exists and AstroStack can open it."),
    Case(error: InspectError.noFolders, names: "", english: "Choose a capture folder first."),
    Case(
      error: CalibrationError.unreadableLibrary("/lib"), names: "/lib",
      english: "The calibration library /lib cannot be read."),
    Case(
      error: CalibrationError.masterFailed(name: "master_BIAS", reason: "no frames"),
      names: "master_BIAS", english: "Siril could not build the master master_BIAS: no frames"),
  ]

  @Test("every Siril and import error has an English and a French sentence", arguments: cases)
  func testEverySirilAndImportErrorHasASentence(_ row: Case) {
    let error = UserFacingError(row.error)
    #expect(error.message.text("en") == row.english)
    let french = error.message.text("fr")
    #expect(french != row.english, "a French sentence, not the English fallback")
    #expect(row.names.isEmpty || french.contains(row.names))
    #expect(!french.contains("Error"), "never the raw enum")
  }

  /// A Swift error with no sentence of its own, carrying the path the user must act on.
  struct BrokenFrame: Error { let path: String }

  @Test("a foreign error keeps its description and payload; a wrapped one is not wrapped twice")
  func testOtherErrors() {
    let posix = NSError(domain: NSPOSIXErrorDomain, code: 13)
    #expect(UserFacingError(posix) == .other(posix.localizedDescription))
    let broken = UserFacingError(BrokenFrame(path: "/c/M31/L_0042.fits"))
    #expect(broken.message.text("fr").contains("/c/M31/L_0042.fits"), "the frame stays named")
    #expect(UserFacingError(UserFacingError.projectClosed) == .projectClosed)
    #expect(UserFacingError.projectClosed.message.text("fr").contains("rouvrez"))
  }

  @Test("the sentences that list valid values list every case, in both languages")
  func testValueListsMatchTheEnums() {
    for language in ["en", "fr"] {
      let filterSet = UserFacingError(InspectError.unknownFilterSet("x")).message.text(language)
      #expect(FilterSet.allCases.allSatisfy { filterSet.contains($0.rawValue) })
      let colour = UserFacingError(InspectError.unknownColorChoice("x")).message.text(language)
      #expect(ColorChoice.allCases.allSatisfy { colour.contains($0.rawValue) })
    }
  }
}

extension LocalizedStringResource {
  /// The resource resolved in `language` (`"fr"`, `"en"`), whatever the host's languages.
  func text(_ language: String) -> String {
    var resource = self
    resource.locale = Locale(identifier: language)
    return String(localized: resource)
  }
}
