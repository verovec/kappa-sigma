package import SwiftUI

/// A histogram with a stretch's three handles drawn over it, draggable (card 0085).
///
/// `handles` holds one set of positions per channel (`STFParameters.handlePositions(in:)`), drawn
/// in that channel's plot colour; a press takes the nearest handle within reach and the drag
/// reports its new position (0…1 of the axis) through `onDrag`. The caller turns it into a
/// stretch (`STFParameters.dragging`) — the component holds no state of its own. 0089's process
/// panels reuse it.
package struct HistogramHandles: View {
  /// The handle a press took.
  package struct Hit: Equatable, Sendable {
    /// Its channel (the index in `handles`).
    package let channel: Int
    /// Which of the three.
    package let handle: STFHandle
  }

  /// Reach of a press around a handle, as a fraction of the axis.
  package static let reach = 0.03

  private let bins: [[Int]]
  private let handles: [STFHandlePositions]?
  private let key: String
  private let label: LocalizedStringResource
  private let hint: LocalizedStringResource
  private let onDrag: (Int, STFHandle, Double) -> Void
  private let onDragEnded: () -> Void
  @State private var dragged: Hit?

  /// The plot of `bins` with `handles` over it (none without a stretch); `key` identifies the
  /// canvas (`AccessibilityID.histogram`), `label` names it and `hint` says what a drag does;
  /// `onDragEnded` tells the caller the drag is over (a drag maps from the stretch at press time).
  package init(
    bins: [[Int]], handles: [STFHandlePositions]?, key: String, label: LocalizedStringResource,
    hint: LocalizedStringResource, onDragEnded: @escaping () -> Void = {},
    onDrag: @escaping (Int, STFHandle, Double) -> Void
  ) {
    self.bins = bins
    self.handles = handles
    self.key = key
    self.label = label
    self.hint = hint
    self.onDrag = onDrag
    self.onDragEnded = onDragEnded
  }

  package var body: some View {
    GeometryReader { geometry in
      ZStack {
        HistogramView(bins: bins)
        Canvas { context, size in
          Self.draw(handles ?? [], channels: bins.count, in: &context, size: size)
        }
      }
      .contentShape(Rectangle())
      .gesture(drag(width: geometry.size.width))
    }
    .accessibilityElement()
    .accessible(.histogram(key, .canvas), label: label)
    .accessibilityHint(Text(hint))
  }

  /// The nearest handle to `position` among `sets`, within `reach`; `nil` when none is close.
  nonisolated package static func nearest(
    to position: Double, in sets: [STFHandlePositions], within reach: Double
  )
    -> Hit?
  {
    var best: (hit: Hit, distance: Double)?
    for (channel, set) in sets.enumerated() {
      for handle in STFHandle.allCases {
        let distance = abs(set[handle] - position)
        if distance <= reach, distance < (best?.distance ?? .infinity) {
          best = (Hit(channel: channel, handle: handle), distance)
        }
      }
    }
    return best?.hit
  }

  /// The plot colour of a channel: luminance for a mono image, R/G/B otherwise.
  nonisolated static func colour(channel: Int, of channels: Int) -> DesignColor {
    channels < 3 ? .plotLuminance : [.plotRed, .plotGreen, .plotBlue][min(channel, 2)]
  }

  /// A line per handle, a triangle at its foot (the midtone's filled), in the channel's colour.
  private static func draw(
    _ sets: [STFHandlePositions], channels: Int, in context: inout GraphicsContext, size: CGSize
  ) {
    for (channel, set) in sets.enumerated() {
      let colour = colour(channel: channel, of: channels).color
      for handle in STFHandle.allCases {
        let x = min(max(set[handle], 0), 1) * size.width
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(colour), lineWidth: 1)
        var foot = Path()
        foot.move(to: CGPoint(x: x - 5, y: size.height))
        foot.addLine(to: CGPoint(x: x + 5, y: size.height))
        foot.addLine(to: CGPoint(x: x, y: size.height - 7))
        foot.closeSubpath()
        if handle == .midtone {
          context.fill(foot, with: .color(colour))
        } else {
          context.stroke(foot, with: .color(colour), lineWidth: 1.5)
        }
      }
    }
  }

  /// A press grabs the nearest handle; the drag moves it along the axis.
  private func drag(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard let handles else { return }
        let axis = max(width, 1)
        if dragged == nil {
          dragged = Self.nearest(
            to: Double(value.startLocation.x / axis), in: handles, within: Self.reach)
        }
        guard let dragged else { return }
        onDrag(dragged.channel, dragged.handle, min(max(Double(value.location.x / axis), 0), 1))
      }
      .onEnded { _ in
        dragged = nil
        onDragEnded()
      }
  }
}
