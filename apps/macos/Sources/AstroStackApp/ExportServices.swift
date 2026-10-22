internal import AppKit
package import Foundation
package import StackKit

/// What the Export stage reaches outside the project (card 0091): StarNet through the host-tool
/// client, a scratch folder for its TIFFs, the home whose read-only sources an export refuses,
/// the clock and zone naming the default folder, and the Finder.
package struct ExportServices: Sendable {
  /// Finds StarNet (the install card re-checks with it).
  package var tools: HostTools
  /// Where StarNet's input and output TIFFs go, removed after each separation.
  package var scratch: URL
  /// The user's home: `~/Documents/astro/{captures,runs,library,fixtures}` are never written.
  package var home: URL
  /// Today, for `exports/<stack>/<yyyy-MM-dd>/`.
  package var now: @Sendable () -> Date
  /// The zone the date is written in: the user's.
  package var timeZone: TimeZone
  /// Shows files in the Finder.
  package var reveal: @MainActor @Sendable ([URL]) -> Void

  /// Services from their parts.
  package init(
    tools: HostTools,
    scratch: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStack/Work/starnet", isDirectory: true),
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current,
    reveal: @escaping @MainActor @Sendable ([URL]) -> Void = { _ in }
  ) {
    self.tools = tools
    self.scratch = scratch
    self.home = home
    self.now = now
    self.timeZone = timeZone
    self.reveal = reveal
  }

  /// The installed StarNet, the real home and clock, the Finder.
  package static let live = Self(
    tools: WelcomeWindow.hostTools,
    reveal: { NSWorkspace.shared.activateFileViewerSelecting($0) })
}
