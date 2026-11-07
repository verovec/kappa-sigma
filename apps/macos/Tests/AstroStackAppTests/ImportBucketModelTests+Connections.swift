import AstroStackApp
import Foundation
import RemoteKit
import Testing

extension ImportBucketModelTests {
  static let second = S3Connection(
    name: "NAS", endpoint: "https://nas.local:9000", region: "us-east-1", pathStyle: true,
    accessKey: "AK2")

  /// Card 0177: the sheet's connections were fixed when it opened, so one added in Settings
  /// while it was up never showed.
  @Test("testConnectionsFollowSettings: a provider change shows in the picker on reload")
  func testConnectionsFollowSettings() {
    var stored = [Self.connection]
    let model = ImportBucketModel(connectionsFrom: { stored }, browsing: FakeBucket().browsing)
    #expect(model.connections == [Self.connection])

    stored.append(Self.second)
    #expect(model.connections == [Self.connection], "nothing moves until a reload")
    model.reloadConnections()
    #expect(model.connections == [Self.connection, Self.second])
  }

  @Test("a connection removed in Settings is no longer the one chosen; a kept one stays chosen")
  func testRemovedConnectionIsUnchosen() {
    var stored = [Self.connection, Self.second]
    let model = ImportBucketModel(connectionsFrom: { stored }, browsing: FakeBucket().browsing)
    model.connectionID = Self.second.id
    model.bucket = "astro"

    stored = [Self.second, Self.connection]
    model.reloadConnections()
    #expect(model.connectionID == Self.second.id && model.bucket == "astro", "reordered: kept")

    stored = [Self.connection]
    model.reloadConnections()
    #expect(model.connectionID == nil, "never a target over a connection that is gone")
    #expect(model.target == nil)
  }

  @Test(
    "an edited chosen connection starts the browse over: its level was listed through the old one")
  func testEditedConnectionStartsOver() async {
    var stored = [Self.connection]
    let fake = FakeBucket()
    let model = ImportBucketModel(connectionsFrom: { stored }, browsing: fake.browsing)
    model.connectionID = Self.connection.id
    model.bucket = "astro"
    model.enter("M31/")
    await model.settled()
    #expect(model.prefix == "M31/" && !model.folders.isEmpty)

    var moved = Self.connection
    moved.endpoint = "https://s3.eu-west-3.amazonaws.com"
    stored = [moved]
    model.reloadConnections()

    #expect(model.connectionID == Self.connection.id, "the same connection, still chosen")
    #expect(model.prefix == "" && model.folders.isEmpty && !model.hasListed)

    model.enter("M31/")
    await model.settled()
    moved.name = "Captures home"
    stored = [moved]
    model.reloadConnections()
    #expect(model.connections == [moved])
    #expect(model.prefix == "M31/" && model.hasListed, "a new name lists nothing differently")
  }

  @Test("following Settings reads at once, then on every change, until the changes end")
  func testFollowSettings() async {
    var stored: [S3Connection] = []
    var reads = 0
    let model = ImportBucketModel(
      connectionsFrom: {
        reads += 1
        return stored
      }, browsing: FakeBucket().browsing)
    stored = [Self.second]
    let (changes, writer) = AsyncStream.makeStream(of: Void.self)
    writer.yield()
    writer.yield()
    writer.finish()

    await model.followSettings(changes)

    #expect(model.connections == [Self.second])
    #expect(reads == 4, "one read at creation, one at once, one per change")
  }
}
