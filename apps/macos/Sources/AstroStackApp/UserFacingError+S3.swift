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

  /// What went wrong with an export's S3 side (card 0152); the service's words kept as sent.
  static func message(_ problem: ExportS3Problem) -> LocalizedStringResource {
    switch problem {
    case .noDestination: .app("Choose where the files go: on this Mac, on S3, or both.")
    case .noBucket: .app("Name the S3 bucket the files go to.")
    case .connectionMissing:
      .app("The S3 connection is gone or has no secret: check Settings › S3 connections.")
    case .captureBucket(let url):
      .app("AstroStack never writes into \(url): captures are read there. Choose another prefix.")
    case .service(let text): .app("S3 refused: \(text)")
    case .uploadFailed(let text):
      .app("Written on this Mac, but the S3 copy failed: \(text). Resend it from the export's row.")
    case .resendNeedsConnection:
      .app("This export does not say which S3 connection it used: export it again.")
    }
  }
}
