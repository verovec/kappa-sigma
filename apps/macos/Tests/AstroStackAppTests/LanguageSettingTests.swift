import AstroStackApp
import Foundation
import Testing

/// The language choice of Settings, stored where Foundation reads it at launch.
@MainActor
@Suite("LanguageSetting — System / Français / English as AppleLanguages")
struct LanguageSettingTests {
  /// A scratch defaults suite, emptied first (clean state at the start).
  static func suite() throws -> (UserDefaults, String) {
    let name = "fr.astrostack.tests.language.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
  }

  @Test(
    "each choice round-trips through AppleLanguages in the app's own domain",
    arguments: zip(
      [LanguageSetting.Choice.french, .english, .system], [["fr"], ["en"], nil] as [[String]?]))
  func testChoiceWritesAppleLanguages(choice: LanguageSetting.Choice, stored: [String]?) throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let setting = LanguageSetting(defaults: defaults, domain: name)
    #expect(setting.choice == .system, "nothing stored: the system's languages")

    setting.choice = choice
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] as? [String] == stored)
    #expect(LanguageSetting(defaults: defaults, domain: name).choice == choice)

    setting.choice = .system
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
  }

  @Test("a per-app language from System Settings (fr-FR) reads as its language")
  func testRegionalIdentifierReadsAsLanguage() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.setPersistentDomain(["AppleLanguages": ["fr-FR"], "other": 1], forName: name)
    let setting = LanguageSetting(defaults: defaults, domain: name)
    #expect(setting.choice == .french)
    setting.choice = .system
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
    #expect(defaults.persistentDomain(forName: name)?["other"] as? Int == 1, "other keys kept")
  }

  @Test("the system's own language list never reads as a choice")
  func testGlobalLanguagesAreNotAChoice() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(defaults.array(forKey: "AppleLanguages") != nil, "the global list falls through")
    #expect(LanguageSetting(defaults: defaults, domain: name).choice == .system)
  }
}
