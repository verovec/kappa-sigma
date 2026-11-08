internal import AppKit
package import Foundation
package import ProcessKit
package import RemoteKit
package import StackKit

/// The S3 client of a Settings connection: `nil` when the connection or its secret is gone.
package typealias S3ClientLookup = @Sendable (UUID) async throws -> S3Client?

/// What the Export stage reaches outside the project (card 0091): StarNet through the host-tool
/// client, a scratch folder for its TIFFs, the home whose read-only sources an export refuses,
/// the clock and zone naming the default folder, and the Finder.
package struct ExportServices: Sendable {
  /// Finds StarNet (the install card re-checks with it).
  package var tools: HostTools
  /// Where StarNet's input and output TIFFs go, removed after each separation.
  package var scratch: URL
  /// The astro folder (Settings, card 0148): its captures, runs, library and fixtures are never
  /// written.
  package var astro: @Sendable () -> URL
  /// Where exports go: the remembered base folder and sub-path template (card 0151).
  package var destination: ExportDestinationSetting
  /// Now, for the template's `{date}` and `{time}`.
  package var now: @Sendable () -> Date
  /// The zone the date is written in: the user's.
  package var timeZone: TimeZone
  /// Shows files in the Finder.
  package var reveal: @MainActor @Sendable ([URL]) -> Void
  /// The S3 client of connection `id` (card 0152), `nil` when it or its secret is gone.
  ///
  /// A Keychain refusal is thrown with its reason; the live lookup reads the Keychain off the
  /// main actor (card 0185).
  package var s3Client: S3ClientLookup
  /// The S3 connections the form offers.
  package var s3Connections: @Sendable () -> [S3Connection]
  /// Puts text on the pasteboard (« Copy S3 URL »).
  package var copy: @MainActor @Sendable (String) -> Void
  /// Where every open project's remote captures are, never an export target (R7 on remote,
  /// card 0180): read on the main actor, where the windows are.
  package var remoteSources: @MainActor @Sendable () -> [RemoteLocation]

  /// Services from their parts.
  package init(
    tools: HostTools,
    scratch: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStack/Work/starnet", isDirectory: true),
    astro: @escaping @Sendable () -> URL = { AstroFolderSetting().folder },
    destination: ExportDestinationSetting = ExportDestinationSetting(),
    now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current,
    reveal: @escaping @MainActor @Sendable ([URL]) -> Void = { _ in },
    s3Client: @escaping S3ClientLookup = Self.liveClient,
    s3Connections: @escaping @Sendable () -> [S3Connection] = { S3ConnectionStore().connections },
    remoteSources: @escaping @MainActor @Sendable () -> [RemoteLocation] = { [] },
    copy: @escaping @MainActor @Sendable (String) -> Void = { _ in }
  ) {
    self.tools = tools
    self.scratch = scratch
    self.astro = astro
    self.destination = destination
    self.now = now
    self.timeZone = timeZone
    self.reveal = reveal
    self.s3Client = s3Client
    self.s3Connections = s3Connections
    self.remoteSources = remoteSources
    self.copy = copy
  }

  /// One URLSession for every export of this run of the app (never one per upload).
  private nonisolated static let transport = HTTPTransport.urlSession()

  /// The client of a connection of Settings, over the app's one transport.
  package nonisolated static let liveClient: S3ClientLookup = { id in
    try await client(id) { S3ConnectionStore() }
  }

  /// The client of connection `id` in the store `store` makes, read off the main actor.
  ///
  /// The Keychain read may wait on the user (an access prompt after a rebuild): never on the
  /// main actor, which draws the windows. `nil` when the connection or its secret is gone; a
  /// Keychain refusal is thrown with its reason.
  @concurrent
  package nonisolated static func client(
    _ id: UUID, in store: @Sendable () -> S3ConnectionStore
  ) async throws -> S3Client? {
    let store = store()
    guard let connection = store.connection(id), let credentials = try store.credentials(for: id)
    else { return nil }
    return S3Client(
      endpoint: try connection.s3Endpoint(), credentials: credentials, transport: transport)
  }

  /// The installed StarNet, the real home and clock, the Finder, the open projects' captures.
  package static let live = Self(
    tools: WelcomeWindow.hostTools,
    reveal: { NSWorkspace.shared.activateFileViewerSelecting($0) },
    remoteSources: { ProjectDocument.openRemoteLocations() },
    copy: { text in
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    })
}
