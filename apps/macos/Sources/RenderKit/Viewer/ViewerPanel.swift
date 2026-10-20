internal import SwiftUI

/// The viewer's controls: every setting visible with its value (R2) — tool, stretch mode and its
/// numbers per channel, clipping overlay, the histogram, and the readout under the cursor.
struct ViewerPanel: View {
  @Bindable var model: ViewerModel

  var body: some View {
    Form {
      Section("View") {
        Picker("Tool", selection: $model.tool) {
          ForEach(ViewerModel.Tool.allCases, id: \.self) { Text($0.rawValue.capitalized) }
        }
        .pickerStyle(.segmented)
        HStack {
          Button("Fit") { model.zoomToFit() }
          Button("1:1") { model.zoomToActualSize() }
          Text(String(format: "%.0f %%", 100 / model.frame.transform.scale)).monospacedDigit()
        }
        Toggle("Clipping overlay", isOn: $model.frame.clippingOverlay)
        HStack {
          Button("Clear region") { model.clearRegion() }.disabled(model.frame.region == nil)
          Button("Clear split") { model.clearSplit() }
        }
        Text("Hold ⌥ to show the reference.").font(.caption).foregroundStyle(.secondary)
      }
      Section("Display stretch") {
        Picker("Mode", selection: $model.stretch) {
          ForEach(ViewerModel.Stretch.allCases, id: \.self) { Text($0.rawValue.capitalized) }
        }
        .pickerStyle(.segmented)
        Toggle("Linked channels", isOn: $model.linked).disabled(model.stretch != .auto)
        stretchNumbers
      }
      Section(model.frame.region == nil ? "Histogram (image)" : "Histogram (region)") {
        HistogramView(bins: model.histogram).frame(height: 120)
      }
      Section("Readout") { readout }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder private var stretchNumbers: some View {
    if model.stretch == .manual {
      ForEach(model.manualSTF.indices, id: \.self) { channel in
        ChannelSliders(
          name: Self.channelName(channel, of: model.manualSTF.count),
          parameters: $model.manualSTF[channel])
      }
    } else if let stf = model.frame.stf {
      ForEach(stf.indices, id: \.self) { channel in
        LabeledContent(Self.channelName(channel, of: stf.count), value: Self.text(stf[channel]))
          .monospacedDigit()
      }
    } else {
      Text("Off: the display is clamp(x).").foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var readout: some View {
    if let readout = model.readout {
      LabeledContent("Pixel", value: "\(readout.x), \(readout.y)")
      ForEach(readout.values.indices, id: \.self) { channel in
        LabeledContent(
          Self.channelName(channel, of: readout.values.count),
          value: String(format: "%.6f", readout.values[channel]))
      }
      if let sky = readout.sky {
        LabeledContent("RA", value: sky.raText)
        LabeledContent("Dec", value: sky.decText)
      }
    } else {
      Text("Move the pointer over the image.").foregroundStyle(.secondary)
    }
  }

  static func channelName(_ index: Int, of count: Int) -> String {
    count < 3 ? "K" : ["R", "G", "B"][min(index, 2)]
  }

  static func text(_ stf: STFParameters) -> String {
    String(format: "c0 %.5f  m %.5f  c1 %.3f", stf.shadows, stf.midtone, stf.highlights)
  }
}

/// Manual stretch of one channel: the three numbers, each with a slider and its value.
private struct ChannelSliders: View {
  let name: String
  @Binding var parameters: STFParameters

  var body: some View {
    VStack(alignment: .leading) {
      Text(name).font(.headline)
      slider("Shadows", value: $parameters.shadows)
      slider("Midtone", value: $parameters.midtone)
      slider("Highlights", value: $parameters.highlights)
    }
  }

  private func slider(_ label: String, value: Binding<Double>) -> some View {
    HStack {
      Text(label).frame(width: 72, alignment: .leading)
      Slider(value: value, in: 0...1)
      Text(String(format: "%.5f", value.wrappedValue)).monospacedDigit().frame(width: 64)
    }
  }
}
