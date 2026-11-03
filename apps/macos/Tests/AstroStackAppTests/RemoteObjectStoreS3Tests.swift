import AstroStackApp
import Foundation
import RemoteKit
import StackKit
import Testing

/// Card 0167: a bucket of Settings scans through `S3Client` (list, ranged GETs) into an inventory
/// of virtual `s3://` paths; the Données line for unchecked frames reads in fr and en.
@Suite("RemoteObjectStore over S3 — the remote scan through the app's client")
struct RemoteObjectStoreS3Tests {
  /// A 4×4 16-bit FITS frame with `cards`, built from the standard.
  static func fits(_ cards: [(String, String)]) -> Data {
    let base = [
      ("SIMPLE", "T"), ("BITPIX", "16"), ("NAXIS", "2"), ("NAXIS1", "4"), ("NAXIS2", "4"),
      ("BZERO", "32768"), ("BSCALE", "1"),
    ]
    var text = (base + cards).map { key, value in
      (key.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + value)
        .padding(toLength: 80, withPad: " ", startingAt: 0)
    }.joined()
    text += "END".padding(toLength: 80, withPad: " ", startingAt: 0)
    while text.utf8.count % 2880 != 0 { text += " " }
    var data = Data(text.utf8)
    data.append(Data(repeating: 0x05, count: 32))
    while data.count % 2880 != 0 { data.append(0) }
    return data
  }

  /// A path-style S3 server over `objects`: ListObjectsV2 and (ranged) GETs.
  static func client(_ objects: [String: Data]) throws -> S3Client {
    let transport = HTTPTransport(
      send: { request in
        let parts = request.url.path.split(separator: "/", maxSplits: 1).map(String.init)
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
        if query?.contains(where: { $0.name == "list-type" }) == true {
          let prefix = query?.first { $0.name == "prefix" }?.value ?? ""
          let contents = objects.keys.filter { $0.hasPrefix(prefix) }.sorted().map { key in
            "<Contents><Key>\(key)</Key><ETag>&quot;e\(key.count)&quot;</ETag>"
              + "<Size>\(objects[key]?.count ?? 0)</Size></Contents>"
          }.joined()
          let xml =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><ListBucketResult>"
            + "<IsTruncated>false</IsTruncated>\(contents)</ListBucketResult>"
          return HTTPResponse(status: 200, body: Data(xml.utf8))
        }
        guard parts.count == 2, let data = objects[parts[1]] else {
          return HTTPResponse(status: 404)
        }
        guard
          let range = request.headers["range"]?.dropFirst("bytes=".count)
            .split(separator: "-").compactMap({ Int($0) }), range.count == 2
        else { return HTTPResponse(status: 200, body: data) }
        let upper = min(range[1], data.count - 1)
        return HTTPResponse(status: 206, body: data.subdata(in: range[0]..<(upper + 1)))
      },
      download: { _, _, _ in HTTPResponse(status: 500) })
    let endpoint = try S3Endpoint(
      url: try #require(URL(string: "http://127.0.0.1:9000")), region: "us-east-1",
      addressing: .pathStyle)
    return S3Client(
      endpoint: endpoint, credentials: S3Credentials(accessKey: "AK", secretKey: "secret"),
      transport: transport)
  }

  @Test("a bucket prefix scans into frames at virtual s3:// paths")
  func testScanThroughS3Client() async throws {
    let light = Self.fits([
      ("IMAGETYP", "'Light Frame'"), ("EXPTIME", "60.0"), ("OBJECT", "'M31'"), ("FILTER", "'L'"),
    ])
    let dark = Self.fits([("IMAGETYP", "'Dark Frame'"), ("EXPTIME", "60.0")])
    let client = try Self.client([
      "night/lights/l_1.fits": light, "night/darks/d_1.fits": dark, "other/x.fits": light,
    ])

    let inventory = try await RemoteScan(
      store: .s3(client, bucket: "astro"), prefix: "night",
      timeZone: TimeZone(identifier: "Europe/Paris") ?? .gmt
    ).inventory()

    #expect(inventory.root == "s3://astro/night")
    #expect(
      inventory.frames.map(\.path).sorted()
        == ["s3://astro/night/darks/d_1.fits", "s3://astro/night/lights/l_1.fits"])
    #expect(Set(inventory.frames.map(\.type)) == [.light, .dark])
  }

  @Test(
    "the unchecked-frames line, in fr and en, singular and plural",
    arguments: [
      (1, "fr", "Contrôles de pixels non vérifiés sur 1 pose (distant)"),
      (3, "fr", "Contrôles de pixels non vérifiés sur 3 poses (distant)"),
      (1, "en", "Pixel checks not run on 1 frame (remote)"),
      (3, "en", "Pixel checks not run on 3 frames (remote)"),
    ])
  func testNotCheckedWords(count: Int, language: String, expected: String) {
    let words = RemoteObjectStore.notCheckedWords(count, locale: Locale(identifier: language))
    #expect(String(localized: words) == expected)
  }
}
