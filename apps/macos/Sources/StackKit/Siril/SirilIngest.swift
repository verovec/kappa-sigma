internal import Foundation

/// How light frames enter a Siril sequence (`siril.SeqIngest`).
///
/// FITS is linked (free); anything else — a NEF, a colour TIFF — must be decoded by `convert`,
/// since `link` only symlinks and Siril would then find no sequence at all.
package enum SirilIngest: Equatable, Sendable {
  case link
  case convert

  /// The extensions `link` can take without decoding.
  static let fitsExtensions: Set<String> = ["fits", "fit", "fts"]

  /// `.link` when every path is FITS (`seqIngest`).
  package init(paths: [String]) {
    let allFITS = paths.allSatisfy {
      Self.fitsExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
    }
    self = allFITS ? .link : .convert
  }

  func command(_ seq: String) -> SirilCommand {
    switch self {
    case .link: .link(seq: seq)
    case .convert: .convert(seq: seq)
    }
  }
}
