internal import AppKit
internal import ProjectKit
internal import RenderKit
package import SwiftUI

/// The Settings window's content: the interface language, applied on relaunch, the runs'
/// scratch folder (card 0098), the stacks' retention (card 0114) and the host tools' status.
package struct SettingsView: View {
  private let setting: LanguageSetting
  private let relaunch: () -> Void
  private let tools: WelcomeModel?
  private let scratch: ScratchSetting
  private let astro: AstroFolderSetting
  private let retention: RetentionSetting
  /// The choice the app was launched with: Relaunch is offered once the choice differs.
  private let launched: LanguageSetting.Choice
  @State private var choice: LanguageSetting.Choice
  @Environment(\.locale) private var locale
  /// The folder runs go to, as last read (the setting is not observable).
  @State private var scratchFolder: URL
  /// The last folder chosen was under the read-only sources (R7) and was not kept.
  @State private var scratchRefused = false
  /// The astro folder, as last read (card 0148).
  @State private var astroFolder: URL
  /// The last astro folder chosen was no folder, or one the app writes under; not kept.
  @State private var astroRefused = false
  /// Which subfolders the root holds, read off the main thread when the root is set (a slow or
  /// unmounted volume never blocks the window), never on each render.
  @State private var astroLines: [(name: String, found: Bool)] = []
  /// The retention policy as edited; written back on every change.
  @State private var policy: RetentionPolicy

  /// Settings over `setting`; `relaunch` restarts the app; `tools` fills the Tools section;
  /// `scratch` is the runs' scratch folder; `retention` the policy for stacks never exported.
  package init(
    setting: LanguageSetting, relaunch: @escaping () -> Void,
    tools: WelcomeModel? = nil, scratch: ScratchSetting = ScratchSetting(),
    astro: AstroFolderSetting = AstroFolderSetting(),
    retention: RetentionSetting = RetentionSetting()
  ) {
    self.setting = setting
    self.relaunch = relaunch
    self.tools = tools
    self.scratch = scratch
    _scratchFolder = State(initialValue: scratch.folder)
    self.astro = astro
    _astroFolder = State(initialValue: astro.folder)
    self.retention = retention
    _policy = State(initialValue: retention.policy)
    launched = setting.choice
    _choice = State(initialValue: setting.choice)
  }

  package var body: some View {
    Form {
      Picker(selection: $choice) {
        Text(.app("System")).tag(LanguageSetting.Choice.system)
        Text(verbatim: "Français").tag(LanguageSetting.Choice.french)
        Text(verbatim: "English").tag(LanguageSetting.Choice.english)
      } label: {
        Text(.app("Language"))
      }
      .onChange(of: choice) { setting.choice = choice }
      HStack {
        Text(.app("The new language applies when AstroStack relaunches."))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(.app("Relaunch"), action: relaunch).disabled(choice == launched)
      }
      scratchSection
      astroSection
      storageSection
      if let tools {
        Section { ToolStrip(model: tools) }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460)
  }

  /// Where Siril's work files go during a run; the next run reads it.
  private var scratchSection: some View {
    Section {
      LabeledContent {
        Text(verbatim: (scratchFolder.path as NSString).abbreviatingWithTildeInPath)
          .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
      } label: {
        Text(.app("Scratch folder"))
      }
      HStack {
        Text(.app("Siril's work files during a run: tens of GB per night, removed when it ends."))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(.app("Choose…"), action: chooseScratch)
        Button(.app("Default")) { pickScratch(nil) }.disabled(scratch.chosen == nil)
      }
      if scratchRefused {
        Text(
          .app(
            "AstroStack never writes under the astro folder: choose a scratch folder outside it.")
        )
        .font(.caption).foregroundStyle(DesignColor.statusError.color)
      }
    }
  }

  /// The root as Settings shows it: `~` for the home folder.
  package nonisolated static func astroPath(_ folder: URL) -> String {
    (folder.path as NSString).abbreviatingWithTildeInPath
  }

  /// The subfolders of the astro root and whether each exists (R2: shown, never decided from).
  @concurrent package nonisolated static func astroLines(
    under root: URL
  ) async -> [(name: String, found: Bool)] {
    AstroFolderSetting.shown.map {
      ($0, AstroFolderSetting.isFolder(root.appendingPathComponent($0, isDirectory: true)))
    }
  }

  /// The read-only data root (card 0148): captures, runs, library, fixtures; every path follows.
  private var astroSection: some View {
    Section {
      LabeledContent {
        Text(verbatim: Self.astroPath(astroFolder))
          .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
      } label: {
        Text(.app("Astro folder"))
      }
      HStack {
        Text(.app("Captures, runs, library and fixtures: read here, never written."))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(.app("Choose…"), action: chooseAstro)
        Button(.app("Default")) { pickAstro(nil) }.disabled(astro.chosen == nil)
      }
      ForEach(astroLines, id: \.name) { line in
        Text(line.found ? .app("\(line.name) — present") : .app("\(line.name) — absent"))
          .font(.caption).foregroundStyle(.secondary)
      }
      if astroRefused {
        Text(.app("Choose an existing folder the app does not write under."))
          .font(.caption).foregroundStyle(DesignColor.statusError.color)
      }
    } header: {
      SectionHeader(
        .app("Astro folder"), help: SettingHelp.help(SettingHelp.astroFolder, locale: locale))
    }
    .task(id: astroFolder) {
      astroLines = await Self.astroLines(under: astroFolder)
    }
  }

  /// Stacks never exported: asked about at launch (the default) or deleted automatically.
  private var storageSection: some View {
    Section {
      Picker(selection: $policy.mode) {
        Text(.app("Ask at launch")).tag(RetentionPolicy.Mode.ask)
        Text(.app("Delete automatically")).tag(RetentionPolicy.Mode.automatic)
      } label: {
        Text(.app("Stacks never exported"))
      }
      Stepper(value: $policy.days, in: RetentionSetting.dayRange) {
        Text(.app("Unused for more than \(policy.days) days"))
      }
      Text(.app("An exported stack and each project's newest are always kept."))
        .font(.caption).foregroundStyle(.secondary)
    } header: {
      SectionHeader(.app("Storage"), help: SettingHelp.help(SettingHelp.storage, locale: locale))
    }
    .onChange(of: policy) { retention.policy = policy }
  }

  private func chooseScratch() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    pickScratch(url)
  }

  private func pickScratch(_ url: URL?) {
    scratchRefused = !scratch.choose(url)
    scratchFolder = scratch.folder
  }

  private func chooseAstro() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.directoryURL = astroFolder
    guard panel.runModal() == .OK, let url = panel.url else { return }
    pickAstro(url)
  }

  private func pickAstro(_ url: URL?) {
    astroRefused = !astro.choose(url)
    astroFolder = astro.folder
  }
}
