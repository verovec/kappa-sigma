package import Foundation
internal import Observation
internal import ProcessKit

/// Settings › Export as the window shows it (card 0151): the base folder, the sub-path template,
/// an example of the folder they name, and why the last choice was refused.
///
/// The view reads it; tests drive it. A refused base or template stores nothing: the setting
/// keeps the last accepted value and the reason is shown.
@Observable
package final class ExportDestinationModel {
  /// The base now.
  package private(set) var base: URL
  /// The template as typed; each edit that names a folder is stored, the others are refused.
  package var template: String {
    get { text }
    set {
      text = newValue
      templateRefusal = setting.choose(template: newValue).map(UserFacingError.exportTemplate)
      if templateRefusal == nil { stored = newValue }
    }
  }
  /// Why the last base picked was not kept.
  package private(set) var baseRefusal: UserFacingError?
  /// Why the template as typed is not kept.
  package private(set) var templateRefusal: UserFacingError?
  private var text: String
  /// The template the setting held when last read or written: `reload` follows the setting only
  /// when it moved, never over a draft being typed.
  @ObservationIgnored private var stored: String
  @ObservationIgnored private let setting: ExportDestinationSetting
  @ObservationIgnored private let now: () -> Date

  /// The model over `setting`; `now` dates the example.
  package init(
    setting: ExportDestinationSetting = ExportDestinationSetting(),
    now: @escaping () -> Date = Date.init
  ) {
    self.setting = setting
    self.now = now
    base = setting.base
    let current = setting.template.text
    text = current
    stored = current
  }

  /// Rereads the setting after another window changed it (the Export stage's « Remember as
  /// default »); a template being typed is kept unless the stored one moved.
  package func reload() {
    base = setting.base
    let current = setting.template.text
    guard current != stored else { return }
    stored = current
    text = current
    templateRefusal = nil
  }

  /// Whether a base was chosen (Default has something to undo).
  package var chosen: Bool { setting.chosenBase != nil }

  /// The base as shown: `~` for the home folder.
  package var path: String { ExportForm.shown(base) }

  /// The folder an export of « M 31 » would go to now, as shown; `nil` while the template is
  /// refused.
  package var example: String? {
    var values = ExportPathTemplate.Values.example
    values.date = now()
    values.zone = .current
    return (try? ExportPathTemplate(template).folder(under: base, values)).map(ExportForm.shown)
  }

  /// Chooses `url` as the base (`nil` = back to the default); a refused one keeps the base and
  /// says why.
  package func pick(_ url: URL?) {
    baseRefusal = setting.choose(url).map { .exportBaseRefused(path: url?.path ?? "", $0) }
    base = setting.base
  }

  /// Back to the standard template: nothing stored, so it follows the app's default.
  package func resetTemplate() {
    setting.choose(template: nil)
    text = ExportPathTemplate.standard
    stored = text
    templateRefusal = nil
  }
}
