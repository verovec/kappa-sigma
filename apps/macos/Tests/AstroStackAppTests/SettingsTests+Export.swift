import AppKit
import AstroStackApp
import Foundation
import ProcessKit
import SwiftUI
import TestSupport
import Testing

extension SettingsTests {
  @Test(
    "testExportSection: base with ~, template kept or refused with why, an example (card 0151)",
    .scratchDirectory, arguments: ["en", "fr"])
  func testExportSection(_ language: String) throws {
    let name = "fr.astrostack.tests.settings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let scratch = try ScratchDirectory.url
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let export = ExportDestinationModel(
      setting: ExportDestinationSetting(
        suite: name, home: home, scratch: scratch.appendingPathComponent("work"),
        temporary: scratch.appendingPathComponent("tmp")),
      now: { Date(timeIntervalSince1970: 0) })
    #expect(export.path == "~/Pictures/AstroStack" && !export.chosen, "the default, with ~")
    #expect(export.template == ExportPathTemplate.standard)
    #expect(export.example?.hasPrefix("~/Pictures/AstroStack/M 31/stack/") == true)

    let nas = scratch.appendingPathComponent("NAS")
    try FileManager.default.createDirectory(at: nas, withIntermediateDirectories: true)
    export.pick(nas)
    #expect(export.chosen && export.baseRefusal == nil && export.base.path == nas.path)
    let missing = scratch.appendingPathComponent("missing")
    export.pick(missing)
    #expect(export.baseRefusal == .exportBaseRefused(path: missing.path, .notAFolder))
    #expect(export.base.path == nas.path, "a refused pick keeps the base")

    export.template = "{object}"
    #expect(export.templateRefusal == nil && export.example == ExportForm.shown(nas) + "/M 31")
    #expect(export.baseRefusal != nil, "editing the template never hides the base's refusal")
    export.template = "{target}"
    #expect(
      export.templateRefusal
        == .exportTemplate(.unknownToken("target", valid: ExportPathTemplate.tokens)))
    #expect(export.example == nil)
    #expect(
      ExportDestinationSetting(suite: name, home: home).template.text == "{object}",
      "the last accepted template is kept")
    // A reload keeps the draft being typed while the stored template did not move…
    export.reload()
    #expect(export.template == "{target}")
    // …and follows another window's « Remember as default ».
    ExportDestinationSetting(suite: name, home: home).choose(template: "{stack}")
    export.reload()
    #expect(export.template == "{stack}" && export.templateRefusal == nil)
    export.resetTemplate()
    #expect(export.templateRefusal == nil && export.template == ExportPathTemplate.standard)
    #expect(defaults.string(forKey: ExportDestinationSetting.templateKey) == nil, "key cleared")

    let view = SettingsView(
      setting: LanguageSetting(defaults: defaults, domain: name), relaunch: {}, export: export)
    let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language)))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 460 && host.fittingSize.height > 0)
    export.pick(nil)
    #expect(!export.chosen && export.path == "~/Pictures/AstroStack")
  }
}
