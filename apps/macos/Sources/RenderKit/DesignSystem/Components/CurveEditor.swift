package import SwiftUI

/// A curve's control-point editor.
///
/// Click to add a point, drag to move it, double-click to remove it. The drawn curve comes from
/// `curve` (the app passes the process's own spline), so what the editor shows is what the
/// process applies.
package struct CurveEditor: View {
  private let label: LocalizedStringResource
  @Binding private var points: CurveEditorPoints
  private let curve: ([SIMD2<Double>]) -> (Double) -> Double
  private let tint: DesignColor
  private let key: String?
  @State private var dragged: Int?
  /// Reach of a click around a point, in curve units.
  private static let reach = 0.04

  /// An editor of `points`, drawing `curve(points)` (built once per change, sampled per column)
  /// in `tint`, the channel's plot colour.
  package init(
    _ label: LocalizedStringResource, points: Binding<CurveEditorPoints>,
    tint: DesignColor = .plotLuminance, key: String? = nil,
    curve: @escaping ([SIMD2<Double>]) -> (Double) -> Double
  ) {
    self.key = key
    self.label = label
    _points = points
    self.tint = tint
    self.curve = curve
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      HStack {
        Text(label)
        Spacer()
        Button {
          points.reset()
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .disabled(points.isIdentity)
        .help(Text(.renderKit("Reset to default")))
        .accessible(key.map { .curve($0, .reset) }, label: .renderKit("Reset to default"))
      }
      GeometryReader { geometry in
        canvas(size: geometry.size)
      }
      .aspectRatio(1, contentMode: .fit)
      .accessibilityElement()
      .accessible(key.map { .curve($0, .canvas) }, label: label)
      .accessibilityHint(
        Text(.renderKit("Click to add a point, drag to move it, double-click to remove it")))
    }
  }

  private func canvas(size: CGSize) -> some View {
    Canvas { context, size in
      let frame = CGRect(origin: .zero, size: size)
      context.fill(Path(frame), with: .color(DesignColor.plotBackground.color))
      var grid = Path()
      for step in 1..<4 {
        let quarter = CGFloat(step) / 4
        grid.move(to: CGPoint(x: quarter * size.width, y: 0))
        grid.addLine(to: CGPoint(x: quarter * size.width, y: size.height))
        grid.move(to: CGPoint(x: 0, y: quarter * size.height))
        grid.addLine(to: CGPoint(x: size.width, y: quarter * size.height))
      }
      context.stroke(
        grid, with: .color(DesignColor.plotLuminance.color.opacity(0.25)), lineWidth: 0.5)
      var diagonal = Path()
      diagonal.move(to: CGPoint(x: 0, y: size.height))
      diagonal.addLine(to: CGPoint(x: size.width, y: 0))
      context.stroke(
        diagonal, with: .color(DesignColor.plotLuminance.color.opacity(0.4)), lineWidth: 1)
      context.stroke(curvePath(size), with: .color(tint.color), lineWidth: 1.5)
      for point in points.points {
        let centre = Self.view(point, size)
        let dot = Path(ellipseIn: CGRect(x: centre.x - 4, y: centre.y - 4, width: 8, height: 8))
        context.fill(dot, with: .color(tint.color))
      }
    }
    .gesture(drag(size))
    .simultaneousGesture(removal(size))
  }

  private func curvePath(_ size: CGSize) -> Path {
    var path = Path()
    let sample = curve(points.points)
    let steps = max(2, Int(size.width))
    for step in 0...steps {
      let x = Double(step) / Double(steps)
      let point = Self.view(SIMD2(x, min(max(sample(x), 0), 1)), size)
      if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    return path
  }

  /// A press grabs the nearest point or adds one; the drag moves it.
  private func drag(_ size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let location = Self.curve(value.location, size)
        if dragged == nil {
          let start = Self.curve(value.startLocation, size)
          if let index = points.nearest(to: start, within: Self.reach) {
            dragged = index
          } else {
            points.add(start)
            dragged = points.nearest(to: start, within: Self.reach)
          }
        }
        if let dragged { points.move(dragged, to: location) }
      }
      .onEnded { _ in dragged = nil }
  }

  private func removal(_ size: CGSize) -> some Gesture {
    SpatialTapGesture(count: 2).onEnded { value in
      if let index = points.nearest(to: Self.curve(value.location, size), within: Self.reach) {
        points.remove(index)
      }
    }
  }

  /// Curve units (y up) to view points (y down).
  static func view(_ point: SIMD2<Double>, _ size: CGSize) -> CGPoint {
    CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
  }

  /// View points to curve units.
  static func curve(_ location: CGPoint, _ size: CGSize) -> SIMD2<Double> {
    SIMD2(
      Double(location.x / max(size.width, 1)), Double(1 - location.y / max(size.height, 1)))
  }
}
