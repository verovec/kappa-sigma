import ProcessKit
import Testing

extension ExportTests {
  struct RemoteRow: Sendable, CustomTestStringConvertible {
    let label: String
    let bucket: String
    let prefix: String
    let refused: Bool
    var testDescription: String { label }
  }

  /// The captures of an open project live at `astro/captures/M31` (a `remote_night` source).
  static let captures = [RemoteLocation(bucket: "astro", prefix: "captures/M31/")]

  static let remoteRows: [RemoteRow] = [
    RemoteRow(
      label: "the capture prefix itself", bucket: "astro", prefix: "captures/M31", refused: true),
    RemoteRow(
      label: "a sub-prefix of it", bucket: "astro", prefix: "/captures/M31/exports/",
      refused: true),
    RemoteRow(
      label: "a sibling prefix", bucket: "astro", prefix: "captures/M31-exports", refused: false),
    RemoteRow(
      label: "another folder of the bucket", bucket: "astro", prefix: "exports", refused: false),
    RemoteRow(
      label: "another bucket, same prefix", bucket: "deliverables", prefix: "captures/M31",
      refused: false),
    RemoteRow(
      label: "the bucket root above the captures", bucket: "astro", prefix: "", refused: false),
  ]

  @Test("R7 on S3: never export into a capture bucket/prefix or under it", arguments: remoteRows)
  func testRemoteCaptureBucketRefused(row: RemoteRow) {
    let refusal = ExportGuard.remoteRefusal(
      RemoteLocation(bucket: row.bucket, prefix: row.prefix), sources: Self.captures)
    #expect((refusal != nil) == row.refused)
  }

  @Test("a whole-bucket source refuses every prefix of that bucket")
  func testRemoteWholeBucketSource() {
    let sources = [RemoteLocation(bucket: "astro", prefix: "")]
    #expect(
      ExportGuard.remoteRefusal(RemoteLocation(bucket: "astro", prefix: "x"), sources: sources)
        != nil)
    #expect(
      ExportGuard.remoteRefusal(RemoteLocation(bucket: "other", prefix: "x"), sources: sources)
        == nil)
  }
}
