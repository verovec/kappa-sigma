import AstroStackApp
import Foundation
import TestSupport
import Testing

/// Whether this host has a login Keychain to write to: probed with a throwaway item, so the suite
/// runs wherever one exists (CI included) and skips, saying why, where none does.
enum KeychainProbe {
  static let usable: Bool = {
    let store = SecretStore.keychain(service: "AstroStack.tests.probe.\(UUID().uuidString)")
    let account = UUID().uuidString
    defer { try? store.delete(account) }
    return (try? store.write(account, "probe")) != nil
  }()
}

/// The live secret store on this Mac's login Keychain, under a throwaway service (card 0150).
///
/// A `Live` suite: the fast loop (`--skip Live`) never touches the user's Keychain. Gated on a
/// probe rather than `.liveFixtures` (it needs a Keychain, not the astro fixtures), so the full
/// run and CI exercise it wherever a login Keychain answers.
@Suite(
  "Keychain secret store — write, read, replace, delete on the host Keychain",
  .enabled(if: KeychainProbe.usable, "no writable login Keychain on this host"), .tags(.live),
  .serialized)
struct LiveKeychainSecretStoreTests {
  @Test("a secret round-trips, is replaced in place, and is gone after delete")
  func testRoundTrip() throws {
    let service = "AstroStack.tests.\(UUID().uuidString)"
    let store = SecretStore.keychain(service: service)
    let account = UUID().uuidString
    defer { try? store.delete(account) }

    #expect(try store.read(account) == nil)
    #expect(try store.contains(account) == false)
    try store.write(account, "first secret")
    #expect(try store.contains(account))
    #expect(try store.read(account) == "first secret")
    try store.write(account, "second secret")
    #expect(try store.read(account) == "second secret", "write replaces, never duplicates")
    #expect(try SecretStore.keychain(service: "\(service).other").read(account) == nil)
    try store.delete(account)
    #expect(try store.read(account) == nil)
    try store.delete(account)  // deleting a missing secret is not an error
  }

  @Test("a Keychain status reads as the system's sentence")
  func testErrorMessage() {
    #expect(KeychainError(status: -25300).message.isEmpty == false)
    #expect(KeychainError(status: -25300).message != "OSStatus -25300")
  }
}
