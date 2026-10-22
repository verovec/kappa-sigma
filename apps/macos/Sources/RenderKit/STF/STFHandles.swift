/// Which values a histogram's axis shows: the linear data, or what the stretch displays.
package enum HistogramDomain: String, CaseIterable, Sendable {
  /// Bins of the linear values.
  case linear
  /// Bins of the displayed values (after the STF).
  case display
}

/// A stretch's three handles on a histogram.
package enum STFHandle: CaseIterable, Sendable {
  /// The black point c0.
  case shadows
  /// The midtone, drawn where the linear value c0 + m·(c1 − c0) sits.
  case midtone
  /// The white point c1.
  case highlights

  /// Its place in `allCases`.
  package var index: Int {
    switch self {
    case .shadows: 0
    case .midtone: 1
    case .highlights: 2
    }
  }
}

/// Where the three handles sit on an axis, as fractions 0…1 of its width.
package struct STFHandlePositions: Equatable, Sendable {
  /// The black point's position.
  package var shadows: Double
  /// The midtone's position.
  package var midtone: Double
  /// The white point's position.
  package var highlights: Double

  /// The three positions.
  package init(shadows: Double, midtone: Double, highlights: Double) {
    self.shadows = shadows
    self.midtone = midtone
    self.highlights = highlights
  }

  /// The position of `handle`.
  package subscript(handle: STFHandle) -> Double {
    switch handle {
    case .shadows: shadows
    case .midtone: midtone
    case .highlights: highlights
    }
  }
}

extension STFParameters {
  /// The least c1 − c0 a drag leaves: one 16-bit step.
  package static let minimumRange = 1.0 / 65535

  /// The linear value displayed at ½: c0 + m·(c1 − c0).
  package var midtoneValue: Double { shadows + midtone * (highlights - shadows) }

  /// Where the handles sit on an axis of `domain`: the values themselves, or 0 / ½ / 1 once
  /// displayed.
  package func handlePositions(in domain: HistogramDomain) -> STFHandlePositions {
    switch domain {
    case .linear:
      STFHandlePositions(shadows: shadows, midtone: midtoneValue, highlights: highlights)
    case .display:
      STFHandlePositions(shadows: 0, midtone: 0.5, highlights: 1)
    }
  }

  /// The linear value shown at `position` of `domain`: the position itself, or the inverse of
  /// `display` (the MTF with 1 − m undoes the MTF with m).
  package func linearValue(atPosition position: Double, in domain: HistogramDomain) -> Double {
    switch domain {
    case .linear:
      position
    case .display:
      shadows + MTF.apply(1 - midtone, min(max(position, 0), 1)) * (highlights - shadows)
    }
  }

  /// The stretch after `handle` is dropped at `position`.
  ///
  /// The value shown there becomes the black point, the midtone or the white point; the other
  /// two numbers stay. The black point stays below the white point by at least `minimumRange`,
  /// both inside [0, 1].
  package func dragging(_ handle: STFHandle, to position: Double, in domain: HistogramDomain)
    -> STFParameters
  {
    let value = min(max(linearValue(atPosition: position, in: domain), 0), 1)
    var result = self
    switch handle {
    case .shadows:
      result.shadows = max(0, min(value, highlights - Self.minimumRange))
    case .highlights:
      result.highlights = min(1, max(value, shadows + Self.minimumRange))
    case .midtone:
      let range = highlights - shadows
      result.midtone = range > 0 ? min(max((value - shadows) / range, 0), 1) : midtone
    }
    return result
  }
}
