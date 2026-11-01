package import Foundation
package import RemoteKit

/// One named S3 connection of Settings (card 0150): where and as whom, never the secret.
///
/// Sources and exports keep the `id`, never the name, so a rename follows everywhere. The secret
/// lives in the Keychain under the id (`S3ConnectionStore`).
package nonisolated struct S3Connection: Codable, Equatable, Identifiable, Sendable {
  /// The stable identity: the Keychain account and what sources and exports store.
  package var id: UUID
  /// The name the user gave, unique among connections.
  package var name: String
  /// `https://…` (or `http://` on localhost for a MinIO in development).
  package var endpoint: String
  /// The signing region (`us-east-1` when left empty).
  package var region: String
  /// Path-style addressing (MinIO, Garage) rather than virtual host (AWS).
  package var pathStyle: Bool
  /// The access key id; not a secret, shown in the list.
  package var accessKey: String

  /// A connection; a new one gets a fresh id.
  package init(
    id: UUID = UUID(), name: String, endpoint: String, region: String, pathStyle: Bool,
    accessKey: String
  ) {
    self.id = id
    self.name = name
    self.endpoint = endpoint
    self.region = region
    self.pathStyle = pathStyle
    self.accessKey = accessKey
  }

  /// The RemoteKit endpoint it names.
  package func s3Endpoint() throws -> S3Endpoint {
    guard let url = URL(string: endpoint) else { throw S3Error.invalidEndpoint(endpoint) }
    return try S3Endpoint(
      url: url, region: region, addressing: pathStyle ? .pathStyle : .virtualHost)
  }
}
