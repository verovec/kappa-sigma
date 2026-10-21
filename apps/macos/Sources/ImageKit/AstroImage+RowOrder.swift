extension AstroImage {
  /// This image with its rows stored in `order`.
  ///
  /// The same image when they already are, else a copy with the rows reversed. Pixels of two
  /// images pair up only in one row order (a starless read from a top-down TIFF against a
  /// bottom-up FITS original).
  package func inRowOrder(_ order: RowOrder) -> AstroImage {
    guard metadata.rowOrder != order else { return self }
    var metadata = metadata
    metadata.rowOrder = order
    let planes = planes.map { plane in
      (0..<height).reversed().flatMap { row in plane[(row * width)..<((row + 1) * width)] }
    }
    return AstroImage(width: width, height: height, planes: planes, metadata: metadata)
  }
}
