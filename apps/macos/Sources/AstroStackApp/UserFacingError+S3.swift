internal import Foundation

extension UserFacingError {
  /// Why an S3 connection was not saved or removed (card 0150).
  static func message(_ refusal: S3ConnectionStore.Refusal) -> LocalizedStringResource {
    switch refusal {
    case .emptyName: .app("Name the connection, for example Captures.")
    case .duplicateName(let name): .app("Another connection is already named \(name).")
    case .notAnEndpoint(let text):
      .app("\(text) is not an endpoint: write it as https://host or https://host:port.")
    case .endpointWithPath(let text):
      .app("\(text) has a path: an endpoint is https://host[:port], the bucket is chosen apart.")
    case .unreadableList:
      .app("The saved S3 connections cannot be read (a newer AstroStack?): nothing was changed.")
    case .insecureEndpoint(let text):
      .app("\(text) would send the keys in the clear: use https (http only on this Mac).")
    case .emptyAccessKey: .app("Enter the access key.")
    case .secretMissing:
      .app("Enter the secret key: it goes to the Keychain and is never shown again.")
    case .keychain(let error): .app("The Keychain refused: \(error.message)")
    }
  }
}
