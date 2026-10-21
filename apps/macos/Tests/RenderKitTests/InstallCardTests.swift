import Foundation
import RenderKit
import Testing

/// The install card of a missing host tool: « Re-check » asks the locator again and shows what it
/// found; nothing falls back to another tool (R2).
@MainActor
@Suite("InstallCard — re-check asks the locator")
struct InstallCardTests {
  /// A locator answering from a list, one answer per call; `hold` keeps each call waiting until
  /// `release()`.
  actor Locator {
    private var answers: [URL?]
    private(set) var calls = 0
    private let hold: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ answers: [URL?], hold: Bool = false) {
      self.answers = answers
      self.hold = hold
    }

    func locate() async -> URL? {
      calls += 1
      if hold { await withCheckedContinuation { waiting.append($0) } }
      return answers.isEmpty ? nil : answers.removeFirst()
    }

    func release() {
      waiting.forEach { $0.resume() }
      waiting = []
    }
  }

  @Test("re-check calls the locator and shows the tool once it is installed")
  func testRecheckCallsLocator() async {
    let siril = URL(fileURLWithPath: "/Applications/Siril.app/Contents/MacOS/siril-cli")
    let locator = Locator([nil, siril])
    let model = InstallCardModel { await locator.locate() }
    #expect(model.state == .missing)
    #expect(await locator.calls == 0, "the card shows the verdict it was given, it does not probe")

    await model.recheck()
    #expect(await locator.calls == 1)
    #expect(model.state == .missing)

    await model.recheck()
    #expect(await locator.calls == 2)
    #expect(model.state == .found(siril))
  }

  @Test("a found tool that disappears is missing again on the next re-check")
  func testRecheckLosesTool() async {
    let tool = URL(fileURLWithPath: "/opt/homebrew/bin/graxpert")
    let locator = Locator([nil])
    let model = InstallCardModel(state: .found(tool)) { await locator.locate() }
    await model.recheck()
    #expect(model.state == .missing)
  }

  @Test("a re-check while one runs asks nothing: an older answer cannot overwrite a newer one")
  func testRecheckWhileChecking() async {
    let tool = URL(fileURLWithPath: "/opt/homebrew/bin/graxpert")
    let locator = Locator([tool], hold: true)
    let model = InstallCardModel { await locator.locate() }
    let first = Task { await model.recheck() }
    while await locator.calls == 0 { await Task.yield() }
    #expect(model.state == .checking)

    await model.recheck()
    #expect(await locator.calls == 1)
    await locator.release()
    await first.value
    #expect(model.state == .found(tool))
  }

  @Test("the status a state shows, with its words in each language", arguments: ["en", "fr"])
  func testStateStatus(_ language: String) {
    let tool = URL(fileURLWithPath: "/usr/local/bin/starnet2")
    let locale = Locale(identifier: language)
    #expect(InstallCard.status(of: .missing) == .unavailable)
    #expect(InstallCard.status(of: .checking) == .unavailable)
    #expect(InstallCard.status(of: .found(tool)) == .ok)
    let found = String(localized: InstallCard.label(of: .found(tool), locale: locale))
    #expect(found.contains(tool.path))
    let missing = String(localized: InstallCard.label(of: .missing, locale: locale))
    #expect(missing == (language == "fr" ? "Non installé" : "Not installed"))
  }

  @Test(
    "a too old install is flagged, not called missing, in each language", arguments: ["en", "fr"])
  func testOutdatedStatus(_ language: String) {
    #expect(InstallCard.status(of: .outdated(version: "1.2.6")) == .attention)
    let words = String(
      localized: InstallCard.label(
        of: .outdated(version: "1.2.6"), locale: Locale(identifier: language)))
    #expect(words.contains("1.2.6"))
    #expect(
      words
        != String(localized: InstallCard.label(of: .missing, locale: Locale(identifier: language))))
  }
}
