internal import AppKit
internal import RenderKit
package import SwiftUI

/// The Settings window's content: the interface language, applied on relaunch, the runs'
/// scratch folder (card 0098) and the host tools' status.
package struct SettingsView: View {
  private let setting: LanguageSetting
  private let relaunch: () -> Void
  private let tools: WelcomeModel?
  private let scratch: ScratchSetting
  /// The choice the app was launched with: Relaunch is offered once the choice differs.
  private let launched: LanguageSetting.Choice
  @State private var choice: LanguageSetting.Choice
  /// The folder runs go to, as last read (the setting is not observable).
  @State private var scratchFolder: URL
  /// The last folder chosen was under the read-only sources (R7) and was not kept.
  @State private var scratchRefused = false

  /// Settings over `setting`; `relaunch` restarts the app; `tools` fills the Tools section;
  /// `scratch` is the runs' scratch folder.
  package init(
    setting: LanguageSetting, relaunch: @escaping () -> Void,
    tools: WelcomeModel? = nil, scratch: ScratchSetting = ScratchSetting()
  ) {
    self.setting = setting
    self.relaunch = relaunch
    self.tools = tools
    self.scratch = scratch
    _scratchFolder = State(initialValue: scratch.folder)
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
        Text(.app("AstroStack never writes under ~/Documents/astro: choose a folder outside it."))
          .font(.caption).foregroundStyle(DesignColor.statusError.color)
      }
    }
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
}
