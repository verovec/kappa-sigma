internal import Foundation

/// What Siril says it applied (card 0094), shown in the panel: never measured by the app.
package struct ColourCalibrationReport: Equatable, Sendable {
  /// The white-balance factors applied to R, G, B (after renormalisation).
  package var factors: [Double]
  /// The stars the solution used.
  package var stars: Int?
  /// The background reference subtracted per channel.
  package var background: [Double]
  /// Siril's own warnings about the solution (an imprecise fit…).
  package var warnings: [String]

  /// The report in Siril's `lines`, or `nil` without three factors.
  package init?(lines: [String]) {
    // The last K0…K2: the factors applied, after renormalisation.
    let factors = Self.values(lines, prefix: "K")
    guard factors.count == 3 else { return nil }
    self.factors = factors
    background = Self.values(lines, prefix: "B")
    stars =
      lines.lazy.compactMap { line -> Int? in
        guard let range = line.range(of: #"using (\d+) stars"#, options: .regularExpression)
        else { return nil }
        return Int(line[range].split(separator: " ")[1])
      }.first
    warnings = lines.filter { $0.contains("imprecise solution") }
  }

  /// The values of the last `P0:`…`P2:` lines (a `\t(deviation …)` tail dropped).
  private static func values(_ lines: [String], prefix: String) -> [Double] {
    var values: [Int: Double] = [:]
    for line in lines {
      guard line.hasPrefix(prefix), let colon = line.firstIndex(of: ":"),
        let channel = Int(line[line.index(after: line.startIndex)..<colon]),
        (0...2).contains(channel)
      else { continue }
      let text = line[line.index(after: colon)...].split(separator: "\t").first ?? ""
      if let value = Double(text.trimmingCharacters(in: .whitespaces)) { values[channel] = value }
    }
    return values.count == 3 ? (0...2).compactMap { values[$0] } : []
  }
}
