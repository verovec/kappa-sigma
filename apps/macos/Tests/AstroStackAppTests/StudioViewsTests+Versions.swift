import AstroStackApp
import Foundation
import ProcessKit
import Testing

extension StudioViewsTests {
  @Test("the history version failures have their sentence in fr and en (card 0156)")
  func testVersionErrorSentences() {
    let expected = [
      (HistoryError.unknownVersion("v1"), "fr", "Cette version n’est plus conservée."),
      (HistoryError.unknownVersion("v1"), "en", "This version is no longer kept."),
      (
        HistoryError.versionOutOfReach("v1"), "fr",
        "Rétablissez les étapes avant cette version pour la restaurer."
      ),
      (
        HistoryError.versionOutOfReach("v1"), "en",
        "Redo the steps before this version to restore it."
      ),
    ]
    for (error, language, sentence) in expected {
      var message = UserFacingError(error).message
      message.locale = Locale(identifier: language)
      #expect(String(localized: message) == sentence)
    }
  }
}
