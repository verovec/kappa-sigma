internal import SwiftUI

/// 256-bin histogram per channel, log counts, R/G/B overlaid (grey for mono).
struct HistogramView: View {
  let bins: [[Int]]

  var body: some View {
    Canvas { context, size in
      let peak = log1p(Double(bins.joined().max() ?? 0))
      guard peak > 0 else { return }
      let colours: [Color] = bins.count < 3 ? [.gray] : [.red, .green, .blue]
      for (channel, counts) in bins.enumerated() {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (bin, count) in counts.enumerated() {
          let x = size.width * Double(bin) / Double(max(counts.count - 1, 1))
          path.addLine(to: CGPoint(x: x, y: size.height * (1 - log1p(Double(count)) / peak)))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        context.fill(path, with: .color(colours[min(channel, colours.count - 1)].opacity(0.45)))
      }
    }
    .background(Color.black.opacity(0.85))
  }
}
