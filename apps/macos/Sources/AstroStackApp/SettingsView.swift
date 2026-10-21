package import SwiftUI

/// The Settings window's content: the interface language, applied on relaunch, and the host
/// tools' status.
package struct SettingsView: View {
  private let setting: LanguageSetting
  private let relaunch: () -> Void
  private let tools: WelcomeModel?
  /// The choice the app was launched with: Relaunch is offered once the choice differs.
  private let launched: LanguageSetting.Choice
  @State private var choice: LanguageSetting.Choice

  /// Settings over `setting`; `relaunch` restarts the app; `tools` fills the Tools section.
  package init(
    setting: LanguageSetting, relaunch: @escaping () -> Void,
    tools: WelcomeModel? = nil
  ) {
    self.setting = setting
    self.relaunch = relaunch
    self.tools = tools
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
      if let tools {
        Section { ToolStrip(model: tools) }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460)
  }
}
