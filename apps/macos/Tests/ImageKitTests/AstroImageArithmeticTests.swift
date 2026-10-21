import ImageKit
import Testing

/// Plane arithmetic for a background model (card 0072): the difference and the ratio of two
/// images of one shape, a non-positive divisor giving 1, another shape refused.
@Suite("AstroImage arithmetic: subtracting, dividing, shape check")
struct AstroImageArithmeticTests {
  static func image(_ planes: [[Float]], width: Int = 2, height: Int = 2) -> AstroImage {
    AstroImage(
      width: width, height: height, planes: planes, metadata: ImageMetadata(rowOrder: .topDown))
  }

  @Test("subtracting is the plane-wise difference, metadata kept")
  func testSubtracting() throws {
    let result = try Self.image([[1, 2, 3, 4], [5, 6, 7, 8]]).subtracting(
      Self.image([[1, 1, 1, 1], [0.5, 0.5, 0.5, 0.5]]))
    #expect(result.planes == [[0, 1, 2, 3], [4.5, 5.5, 6.5, 7.5]])
    #expect(result.metadata.rowOrder == .topDown && result.width == 2 && result.height == 2)
  }

  @Test("dividing is the plane-wise ratio; a divisor at or below zero gives 1, never a spike")
  func testDividing() throws {
    let result = try Self.image([[1, 2, 3, 4]]).dividing(by: Self.image([[2, 0, -0.5, 8]]))
    #expect(result.planes == [[0.5, 1, 1, 0.5]])
  }

  @Test(
    "another shape is refused",
    arguments: [([[0, 0, 0, 0]], 4, 1), ([[0, 0, 0, 0], [0, 0, 0, 0]], 2, 2)]
      as [([[Float]], Int, Int)])
  func testShapeMismatch(planes: [[Float]], width: Int, height: Int) {
    let image = Self.image([[1, 2, 3, 4]])
    let other = Self.image(planes, width: width, height: height)
    #expect(throws: AstroImageError.shapeMismatch(width: 2, height: 2, planes: 1)) {
      try image.subtracting(other)
    }
    #expect(throws: AstroImageError.shapeMismatch(width: 2, height: 2, planes: 1)) {
      try image.dividing(by: other)
    }
  }
}
