internal import AppKit
internal import ProcessKit
internal import ProjectKit
internal import RenderKit
package import SwiftUI

/// The Settings window's content, one tab each (card 0177): the interface language, applied on
/// relaunch; the scratch (card 0098), astro (0148) and export (0151) folders; the S3 connections
/// (card 0150); the stacks' retention (card 0114); the host tools' status.
package struct SettingsView: View {
  private let setting: LanguageSetting
  private let relaunch: () -> Void
  private let tools: WelcomeModel?
  private let scratch: ScratchSetting
  /// Settings › Astro folder (card 0148), owned by the view: a rebuild keeps its lines.
  @State private var astro: AstroFolderModel
  /// Settings › Export (card 0151), owned by the view like the astro folder.
  @State private var export: ExportDestinationModel
  /// Settings › S3 connections (card 0150), owned by the view like the export folder.
  @State private var s3: S3ConnectionsModel
  /// The tab shown (card 0177), kept by the window across openings.
  private let selection: SettingsSelection
  private let retention: RetentionSetting
  /// The choice the app was launched with: Relaunch is offered once the choice differs.
  private let launched: LanguageSetting.Choice
  @State private var choice: LanguageSetting.Choice
  @Environment(\.locale) private var locale
  /// The folder runs go to, as last read (the setting is not observable).
  @State private var scratchFolder: URL
  /// The last folder chosen was under the read-only sources (R7) and was not kept.
  @State private var scratchRefused = false
  /// The retention policy as edited; written back on every change.
  @State private var policy: RetentionPolicy

  /// Settings over `setting`; `relaunch` restarts the app; `tools` fills the Tools section;
  /// `scratch` is the runs' scratch folder; `retention` the policy for stacks never exported;
  /// `selection` the tab shown.
  package init(
    setting: LanguageSetting, relaunch: @escaping () -> Void,
    tools: WelcomeModel? = nil, scratch: ScratchSetting = ScratchSetting(),
    astro: AstroFolderModel = AstroFolderModel(),
    export: ExportDestinationModel = ExportDestinationModel(),
    s3: S3ConnectionsModel = S3ConnectionsModel(),
    retention: RetentionSetting = RetentionSetting(),
    selection: SettingsSelection = SettingsSelection()
  ) {
    self.setting = setting
    self.relaunch = relaunch
    self.tools = tools
    self.scratch = scratch
    _scratchFolder = State(initialValue: scratch.folder)
    _astro = State(initialValue: astro)
    _export = State(initialValue: export)
    _s3 = State(initialValue: s3)
    self.retention = retention
    self.selection = selection
    _policy = State(initialValue: retention.policy)
    launched = setting.choice
    _choice = State(initialValue: setting.choice)
  }

  package var body: some View {
    TabView(selection: shown) {
      ForEach(tabs) { tab in
        Form { content(of: tab) }
          .formStyle(.grouped)
          .frame(width: SettingsTab.formWidth)
          .frame(minHeight: SettingsTab.formMinHeight)
          .tabItem {
            Label {
              Text(tab.title)
            } icon: {
              Image(systemName: tab.symbol)
            }
          }
          .tag(tab)
      }
    }
    .task(id: astro.folder) { await astro.refresh() }
    // The Export stage's « Remember as default » writes the same setting from another window;
    // here, not on the Folders tab, whose task stops while another tab is shown.
    .task { await DefaultsChanges.follow(DefaultsChanges.live) { export.reload() } }
  }

  /// The selection as shown: a selection the view has no tab for would leave the tab view blank.
  private var shown: Binding<SettingsTab> {
    Binding(
      get: { Self.shown(selection.tab, in: tabs) }, set: { selection.tab = $0 })
  }

  /// The tabs shown: Tools only when there is a tool model to show.
  private var tabs: [SettingsTab] {
    SettingsTab.allCases.filter { $0 != .tools || tools != nil }
  }

  /// `tab` when it is one of `tabs`, General otherwise.
  package static func shown(_ tab: SettingsTab, in tabs: [SettingsTab]) -> SettingsTab {
    tabs.contains(tab) ? tab : .general
  }

  /// The sections of `tab`, each unchanged from the single form they came from.
  @ViewBuilder private func content(of tab: SettingsTab) -> some View {
    switch tab {
    case .general: languageSection
    case .folders:
      scratchSection
      astroSection
      exportSection
    case .s3: S3ConnectionsSection(model: s3)
    case .storage: storageSection
    case .tools:
      if let tools { Section { ToolStrip(model: tools) } }
    }
  }

  /// The interface language, applied when the app relaunches.
  private var languageSection: some View {
    Section {
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
    }
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

  /// The read-only data root (card 0148): captures, runs, library, fixtures; every path follows.
  private var astroSection: some View {
    Section {
      LabeledContent {
        Text(verbatim: astro.path)
          .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
      } label: {
        Text(.app("Astro folder"))
      }
      HStack {
        Text(.app("Captures, runs, library and fixtures: read here, never written."))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(.app("Choose…"), action: chooseAstro)
        Button(.app("Default")) { astro.pick(nil) }.disabled(!astro.chosen)
      }
      ForEach(astro.lines, id: \.name) { line in
        Text(line.found ? .app("\(line.name) — present") : .app("\(line.name) — absent"))
          .font(.caption).foregroundStyle(.secondary)
      }
      if astro.refused {
        Text(.app("Choose an existing folder the app does not write under."))
          .font(.caption).foregroundStyle(DesignColor.statusError.color)
      }
    } header: {
      SectionHeader(
        .app("Astro folder"), help: SettingHelp.help(SettingHelp.astroFolder, locale: locale))
    }
  }

  /// Where exports go (card 0151): the base, the sub-path template, an example of both.
  private var exportSection: some View {
    Section {
      LabeledContent {
        Text(verbatim: export.path)
          .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
      } label: {
        Text(.app("Export folder"))
      }
      HStack {
        Text(.app("Final images go here, never into the project."))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(.app("Choose…"), action: chooseExport)
        Button(.app("Default")) { export.pick(nil) }.disabled(!export.chosen)
      }
      TextField(.app("Sub-folders"), text: $export.template)
      HStack {
        Text(.app("Tokens: \(ExportPathTemplate.listed)"))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(.app("Default")) { export.resetTemplate() }
          .disabled(export.template == ExportPathTemplate.standard)
      }
      if let example = export.example {
        Text(.app("For example \(example)"))
          .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
      exportRefusals
    } header: {
      SectionHeader(.app("Export"), help: SettingHelp.help(SettingHelp.export, locale: locale))
    }
  }

  /// Why the last export base or template was not kept, each on its own line.
  @ViewBuilder private var exportRefusals: some View {
    if let refusal = export.baseRefusal {
      Text(refusal.message).font(.caption).foregroundStyle(DesignColor.statusError.color)
    }
    if let refusal = export.templateRefusal {
      Text(refusal.message).font(.caption).foregroundStyle(DesignColor.statusError.color)
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
    guard let url = FolderPanel.pick(FolderPanel.make(startingIn: nil, canCreate: true)) else {
      return
    }
    pickScratch(url)
  }

  private func pickScratch(_ url: URL?) {
    scratchRefused = !scratch.choose(url)
    scratchFolder = scratch.folder
  }

  private func chooseExport() {
    guard let url = FolderPanel.pick(FolderPanel.make(startingIn: export.base, canCreate: true))
    else {
      return
    }
    export.pick(url)
  }

  private func chooseAstro() {
    guard let url = FolderPanel.pick(FolderPanel.make(startingIn: astro.folder, canCreate: false))
    else {
      return
    }
    astro.pick(url)
  }
}
