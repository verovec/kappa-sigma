package import Foundation

extension FITSFile {
  /// How `downsampled` combines the pixels of a cell.
  package enum Pooling: Sendable {
    /// The average: background and level estimates.
    case mean
    /// The maximum: keeps thin bright features (trails) when shrinking.
    case max
  }

  /// The first plane reduced to at most `maxDimension` on its longer side (`ReadDownsampled`):
  /// the smallest integer factor that fits, cells pooled in double, the last cells ragged.
  package func downsampled(
    maxDimension: Int, pooling: Pooling
  ) throws -> (grid: [Double], width: Int, height: Int) {
    try Self.withPath(path) {
      let layout = try FITSLayout(header: header)
      let (width, height) = (layout.width, layout.height)
      guard body.count >= width * height * layout.bytesPerValue else {
        throw FITSError.truncatedData
      }
      var factor = 1
      while (width + factor - 1) / factor > maxDimension
        || (height + factor - 1) / factor > maxDimension
      {
        factor += 1
      }
      let outWidth = (width + factor - 1) / factor
      let grid = pool(layout: layout, factor: factor, outWidth: outWidth, pooling: pooling)
      return (grid, outWidth, (height + factor - 1) / factor)
    }
  }

  /// The first plane pooled into `factor`-sized cells, rows of `outWidth` cells.
  private func pool(layout: FITSLayout, factor: Int, outWidth: Int, pooling: Pooling) -> [Double] {
    let (width, height) = (layout.width, layout.height)
    let cells = outWidth * ((height + factor - 1) / factor)
    var grid = [Double](repeating: pooling == .max ? -1e308 : 0, count: cells)
    var counts = [Int](repeating: 0, count: cells)
    body.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      for row in 0..<height {
        for column in 0..<width {
          let stored = Self.stored(
            base + (row * width + column) * layout.bytesPerValue, bitpix: layout.bitpix)
          let value = layout.bzero + layout.bscale * stored
          let cell = (row / factor) * outWidth + column / factor
          if pooling == .max {
            grid[cell] = Swift.max(grid[cell], value)
          } else {
            grid[cell] += value
            counts[cell] += 1
          }
        }
      }
    }
    if pooling == .mean {
      for index in grid.indices where counts[index] > 0 { grid[index] /= Double(counts[index]) }
    }
    return grid
  }

  /// Writes the rectangle [x0, x1) × [y0, y1), clamped to the image, as a float32 FITS.
  ///
  /// Physical values (`cropFITS`), the source's other cards kept. Replaces `url` atomically.
  package func writeCrop(to url: URL, x0: Int, y0: Int, x1: Int, y1: Int) throws {
    try Self.withPath(url.path) {
      let image = try image()
      let (left, top) = (Swift.max(0, x0), Swift.max(0, y0))
      let (right, bottom) = (Swift.min(image.width, x1), Swift.min(image.height, y1))
      guard right > left, bottom > top else { throw FITSError.dimensionMismatch }
      let width = right - left
      let planes = image.planes.map { plane in
        (top..<bottom).flatMap { row in
          plane[(row * image.width + left)..<(row * image.width + right)]
        }
      }
      let cards = Self.croppedCards(header.cards, width: width, height: bottom - top)
      var text = cards.map(\.raw).joined() + "END" + String(repeating: " ", count: 77)
      text += String(repeating: " ", count: Self.padding(text.utf8.count))
      var out = Data(text.utf8)
      let data = FITSDecoder.encodeFloat32(planes, bzero: 0, bscale: 1)
      out.append(data)
      out.append(Data(count: Self.padding(data.count)))
      try out.write(to: url, options: .atomic)
    }
  }

  /// The source cards for a float32 image of the new size: BITPIX −32, NAXIS1/2 replaced, no
  /// BZERO/BSCALE (values are physical).
  private static func croppedCards(_ cards: [FITSHeader.Card], width: Int, height: Int)
    -> [FITSHeader.Card]
  {
    cards.compactMap { card in
      switch card.keyword {
      case "BZERO", "BSCALE": nil
      case "BITPIX": FITSHeader.Card(raw: integerCard("BITPIX", -32))
      case "NAXIS1": FITSHeader.Card(raw: integerCard("NAXIS1", width))
      case "NAXIS2": FITSHeader.Card(raw: integerCard("NAXIS2", height))
      default: card
      }
    }
  }

  /// A fixed-format integer card (value right-aligned in columns 11–30).
  private static func integerCard(_ keyword: String, _ value: Int) -> String {
    let key = keyword.padding(toLength: 8, withPad: " ", startingAt: 0)
    let number = String(value)
    let field = String(repeating: " ", count: Swift.max(0, 20 - number.count)) + number
    return (key + "= " + field).padding(toLength: cardLength, withPad: " ", startingAt: 0)
  }
}
