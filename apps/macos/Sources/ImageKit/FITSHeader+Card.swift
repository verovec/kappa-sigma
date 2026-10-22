internal import Foundation

extension FITSHeader.Card {
  /// A `KEY     = value` card in fixed format (FITS 4.2: logical and numeric values end in
  /// column 30, strings start in column 11), padded to 80 characters.
  package init(keyword: String, value: String) {
    let field =
      value.hasPrefix("'") ? value : String(repeating: " ", count: max(0, 20 - value.count)) + value
    let text = keyword.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + field
    self.init(raw: text.padding(toLength: FITSFile.cardLength, withPad: " ", startingAt: 0))
  }

  /// A numeric card: the shortest text that reads back as `number`, with an upper-case exponent.
  package init(keyword: String, number: Double) {
    self.init(keyword: keyword, value: "\(number)".uppercased())
  }
}
