import ImageKit
import Testing

@Suite("AstroImage.inRowOrder: rows reversed only when the order differs")
struct RowOrderTests {
  @Test("a bottom-up 2 × 3 image in top-down order has its rows reversed, columns kept")
  func testFlip() {
    let image = AstroImage(
      width: 2, height: 3, planes: [[1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12]],
      metadata: ImageMetadata(rowOrder: .bottomUp))
    let flipped = image.inRowOrder(.topDown)
    #expect(flipped.planes == [[5, 6, 3, 4, 1, 2], [11, 12, 9, 10, 7, 8]])
    #expect(flipped.metadata.rowOrder == .topDown)
    #expect(image.inRowOrder(.bottomUp) === image)
    #expect(flipped.inRowOrder(.bottomUp).planes == image.planes)
  }
}
