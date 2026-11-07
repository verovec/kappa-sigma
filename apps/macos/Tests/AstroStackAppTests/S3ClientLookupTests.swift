import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import Synchronization
import Testing

/// Card 0185: a connection's client is looked up off the main actor (the Keychain read may
/// block on a prompt), and a Keychain refusal reaches the run with its own words (R2), never
/// read as « no bucket ».
@Suite("S3 client lookup — off the main actor, refusals said")
struct S3ClientLookupTests {
  /// For every secret read, whether it ran on the main thread.
  final class Reads: Sendable {
    private let state = Mutex<[Bool]>([])
    var onMain: [Bool] { state.withLock { $0 } }
    func note() { state.withLock { $0.append(Thread.isMainThread) } }
  }

  /// A secret store over `inner` that notes each read in `reads`.
  static func watching(_ inner: SecretStore, _ reads: Reads) -> SecretStore {
    SecretStore(
      read: { account in
        reads.note()
        return try inner.read(account)
      },
      contains: inner.contains, write: inner.write, delete: inner.delete)
  }

  @MainActor
  @Test("the live lookup reads the Keychain off the main actor, even called from it")
  func testLiveClientReadsTheKeychainOffMain() async throws {
    let fixture = try S3ConnectionStoreTests.Fixture()
    defer { fixture.tearDown() }
    let saved = try fixture.store.save(
      S3ConnectionStoreTests.draft("Exports", endpoint: "http://127.0.0.1:9000"), secret: "s")
    let reads = Reads()
    let secrets = Self.watching(fixture.secrets, reads)
    let name = fixture.name

    let client = try await ExportServices.client(saved.id) {
      S3ConnectionStore(defaults: UserDefaults(suiteName: name) ?? .standard, secrets: secrets)
    }

    #expect(client != nil)
    #expect(reads.onMain == [false], "one read, never on the main thread")
  }

  @Test("an unknown connection is no client; a Keychain refusal is thrown as such")
  func testLookupOutcomes() async throws {
    let fixture = try S3ConnectionStoreTests.Fixture()
    defer { fixture.tearDown() }
    let saved = try fixture.store.save(S3ConnectionStoreTests.draft("Captures"), secret: "s")
    let name = fixture.name
    let refusing = SecretStore(
      read: { _ in throw KeychainError(status: -25293) }, contains: { _ in true },
      write: { _, _ in }, delete: { _ in })

    let unknown = try await ExportServices.client(UUID()) {
      S3ConnectionStore(defaults: UserDefaults(suiteName: name) ?? .standard, secrets: refusing)
    }
    #expect(unknown == nil)
    await #expect(throws: S3ConnectionStore.Refusal.keychain(KeychainError(status: -25293))) {
      _ = try await ExportServices.client(saved.id) {
        S3ConnectionStore(defaults: UserDefaults(suiteName: name) ?? .standard, secrets: refusing)
      }
    }
  }

  @Test("a run's buckets: a Keychain refusal is thrown with its words, never « no bucket »")
  func testRunStoresSurfaceTheKeychainRefusal() async throws {
    let refusal = S3ConnectionStore.Refusal.keychain(KeychainError(status: -25293))
    let sources = [RunStoresTests.source(1, bucket: "astro")]

    await #expect(throws: refusal) {
      _ = try await ImportPlanning.runStores(sources, client: { _ in throw refusal })
    }
    #expect(UserFacingError(refusal) == .s3Connection(refusal), "the run shows the refusal")
  }
}
