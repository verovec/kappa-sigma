package import Foundation
package import ProcessKit
internal import StackKit

/// Where exports go (card 0151): a base folder and a sub-path template, kept in the app's
/// defaults — `~/Pictures/AstroStack` and `{object}/{stack}/{date}-{time}` unless chosen.
///
/// Exports leave the project package: the user picks where deliverables live. The base is never
/// inside the astro folder's read-only sources (R7) nor inside what the app itself writes (the
/// projects, the scratch folder): a refused choice stores nothing and says why.
package nonisolated struct ExportDestinationSetting: Sendable {
  /// The defaults key of the base folder.
  package static let baseKey = "exportBase"
  /// The defaults key of the template.
  package static let templateKey = "exportTemplate"

  /// Why a folder cannot be the base.
  package enum Refusal: Equatable, Sendable {
    /// It is not an existing folder.
    case notAFolder
    /// It is inside the astro folder's captures, runs, library or fixtures.
    case readOnly
    /// It is inside the projects (`~/AstroStack`) or a folder the app works in.
    case appOwned
  }

  /// The defaults suite, `nil` for the app's own: a name, so the setting crosses tasks with the
  /// export services (`UserDefaults` is not `Sendable`).
  private let suite: String?
  private let home: URL
  private let scratch: URL?
  private let temporary: URL

  /// The setting stored in the defaults suite `suite`, the app's own when `nil`.
  ///
  /// `home`, `scratch` and `temporary` locate what the app writes under (as
  /// `AstroFolderSetting`'s).
  package init(
    suite: String? = nil, home: URL = URL(fileURLWithPath: NSHomeDirectory()),
    scratch: URL? = nil, temporary: URL = FileManager.default.temporaryDirectory
  ) {
    self.suite = suite
    self.home = home
    self.scratch = scratch
    self.temporary = temporary
  }

  private var defaults: UserDefaults {
    suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
  }

  /// The base when nothing is chosen: `~/Pictures/AstroStack`.
  package static var defaultBase: URL {
    defaultBase(under: URL(fileURLWithPath: NSHomeDirectory()))
  }

  /// The default base under `home`.
  package static func defaultBase(under home: URL) -> URL {
    pictures(under: home).appendingPathComponent("AstroStack", isDirectory: true)
  }

  private static func pictures(under home: URL) -> URL {
    home.appendingPathComponent("Pictures", isDirectory: true)
  }

  /// The base folder chosen, `nil` for the default.
  package var chosenBase: URL? {
    defaults.string(forKey: Self.baseKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  /// The base now: the chosen folder, else `~/Pictures/AstroStack` under `home`.
  package var base: URL { chosenBase ?? Self.defaultBase(under: home) }

  /// The template now: the one chosen, else the standard one.
  package var template: ExportPathTemplate {
    ExportPathTemplate(defaults.string(forKey: Self.templateKey) ?? ExportPathTemplate.standard)
  }

  /// Why `folder` cannot be the base, or `nil`.
  ///
  /// Where it is comes first: a missing folder inside the read-only sources is refused as such.
  package func refusal(for folder: URL) -> Refusal? {
    if let refusal = placeRefusal(for: folder) { return refusal }
    return AstroFolderSetting.isFolder(folder) ? nil : .notAFolder
  }

  /// Why no export may be written in `folder`, existing or not: inside the read-only sources
  /// (R7), or inside a folder the app writes (a project, the scratch folder the sweep empties).
  package func placeRefusal(for folder: URL) -> Refusal? {
    let astro = AstroFolderSetting(
      defaults: defaults, home: home, scratch: scratch, temporary: temporary)
    if ExportGuard.refusal(for: folder, astro: astro.folder) != nil { return .readOnly }
    let owned = AstroFolderSetting.appOwned(
      defaults: defaults, home: home, scratch: scratch, temporary: temporary)
    return owned.contains { LeftoverSweep.contains($0, folder) } ? .appOwned : nil
  }

  /// Whether `folder` is the default base (remembering it stores nothing).
  package func isDefault(_ folder: URL) -> Bool {
    folder.standardizedFileURL.path == Self.defaultBase(under: home).standardizedFileURL.path
  }

  /// Chooses `folder` as the base (`nil` = back to the default); a refusal stores nothing.
  @discardableResult
  package func choose(_ folder: URL?) -> Refusal? {
    guard let folder else {
      defaults.removeObject(forKey: Self.baseKey)
      return nil
    }
    if let refusal = refusal(for: folder) { return refusal }
    defaults.set(folder.standardizedFileURL.path, forKey: Self.baseKey)
    return nil
  }

  /// Chooses the template `text` (`nil` = back to the standard one); a refusal stores nothing.
  @discardableResult
  package func choose(template text: String?) -> ExportPathTemplate.Refusal? {
    guard let text else {
      defaults.removeObject(forKey: Self.templateKey)
      return nil
    }
    if let refusal = ExportPathTemplate(text).refusal(.example) { return refusal }
    defaults.set(text, forKey: Self.templateKey)
    return nil
  }

  /// Whether an export may create `base` when it is missing: only under `~/Pictures`.
  ///
  /// That is where the default lives; a chosen base that is gone (an unplugged disk) is
  /// reported, never made again on the startup disk.
  package func mayCreate(_ base: URL) -> Bool {
    LeftoverSweep.contains(Self.pictures(under: home), base)
  }
}
