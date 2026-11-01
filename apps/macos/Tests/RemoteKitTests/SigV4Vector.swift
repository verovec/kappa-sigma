import Foundation
import RemoteKit
import Testing

/// One case of the AWS SigV4 test suite, read from `Fixtures/sigv4/<name>.{req,creq,sts,authz}`.
struct SigV4Vector {
  /// The suite's signing time, `20150830T123600Z`.
  static let date = Date(timeIntervalSince1970: 1_440_938_160)

  let raw: String
  let canonicalRequest: String
  let stringToSign: String
  let authorization: String

  static func load(_ name: String) throws -> Self {
    func text(_ ext: String) throws -> String {
      let url = try #require(
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures/sigv4"),
        "missing fixture \(name).\(ext)")
      return try String(contentsOf: url, encoding: .utf8)
    }
    return Self(
      raw: try text("req"), canonicalRequest: try text("creq"), stringToSign: try text("sts"),
      authorization: try text("authz"))
  }

  /// The raw HTTP request decoded: request line, `Name:value` headers, blank line, body.
  func request() throws -> SignableRequest {
    let (head, body) = Self.split(raw)
    var lines = head.components(separatedBy: "\n")
    let requestLine = lines.removeFirst().components(separatedBy: " ")
    let method = requestLine[0]
    let target = requestLine.dropFirst().dropLast().joined(separator: " ")
    let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let path = try #require(String(parts[0]).removingPercentEncoding)
    let query = try parts.count > 1 ? Self.query(String(parts[1])) : []
    let headers = lines.filter { !$0.isEmpty }.map { line in
      let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      return SignableRequest.Header(String(pair[0]), pair.count > 1 ? String(pair[1]) : "")
    }
    return SignableRequest(
      method: method, path: path, query: query, headers: headers,
      payloadHash: Data(body.utf8).sha256Hex)
  }

  private static func split(_ raw: String) -> (head: String, body: String) {
    guard let range = raw.range(of: "\n\n") else { return (raw, "") }
    return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
  }

  private static func query(_ text: String) throws -> [SignableRequest.QueryItem] {
    try text.split(separator: "&").map { pair in
      let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = try #require(String(kv[0]).removingPercentEncoding)
      let value = try #require(kv.count > 1 ? String(kv[1]).removingPercentEncoding : "")
      return SignableRequest.QueryItem(name, value)
    }
  }
}
