internal import Foundation

/// Reads `siril-cli --version` and enforces the 1.4 floor (the scripts use 1.4 syntax that older
/// Siril silently ignores, e.g. `rgbcomp -lum=`).
package enum SirilVersion {
  /// The lowest supported version.
  package static let floor = (major: 1, minor: 4)

  /// The version (`1.4.4`), or an error saying what is wrong with the installation.
  package static func parse(_ output: String) throws -> String {
    guard output.lowercased().contains("siril") else { throw SirilError.notSiril(output: output) }
    let pattern = #"(?i)siril\s+v?(\d+)\.(\d+)(\.\d+)?"#
    guard let range = output.range(of: pattern, options: .regularExpression) else {
      throw SirilError.unreadableVersion(output: output)
    }
    let numbers = output[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    let major = numbers.first ?? 0
    let minor = numbers.dropFirst().first ?? 0
    guard (major, minor) >= floor else { throw SirilError.tooOld(version: "\(major).\(minor)") }
    return numbers.map(String.init).joined(separator: ".")
  }
}
