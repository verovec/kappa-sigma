import AstroStackApp
import Foundation
import Testing

extension WelcomeViewTests {
  /// Card 0177: the welcome window offered New and Open only; Settings… opens it on the last tab.
  @Test("testSettingsButton: « Settings… » beside New and Open, on the last tab shown")
  func testSettingsButton() {
    var asked: [SettingsTab?] = []
    let actions = WelcomeView.Actions(
      open: { _ in }, choose: {}, create: { _ in URL(fileURLWithPath: "/") },
      settings: { asked.append($0) })
    let view = WelcomeView(
      model: WelcomeModel(recentURLs: { [] }, tools: Self.mixedTools), actions: actions)

    let entries = AccessibilityAuditTests.entries(view)
    view.settingsButton.press()

    #expect(
      entries.contains { $0.id == "fr.astrostack.settings.open.last" }, "\(entries.map(\.id))")
    #expect(asked == [nil])
  }
}
