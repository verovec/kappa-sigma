internal import Foundation
internal import SwiftUI

/// The viewer's controls: every setting visible with its value (R2) — tool, stretch mode and its
/// numbers per channel, clipping overlay, the histogram, and the readout under the cursor.
///
/// Words come from RenderKit's catalog and numbers are formatted in the view's `\.locale`.
struct ViewerPanel: View {
  @Bindable var model: ViewerModel
  @Environment(\.locale) private var locale

  var body: some View {
    Form {
      viewSection
      stretchSection
      Section {
        HistogramView(bins: model.histogram).frame(height: 120)
      } header: {
        Text(
          model.frame.region == nil
            ? .renderKit("Histogram (image)") : .renderKit("Histogram (region)"))
      }
      Section {
        readout
      } header: {
        Text(.renderKit("Readout"))
      }
    }
    .formStyle(.grouped)
  }

  /// Tool, zoom, clipping overlay, region and split.
  private var viewSection: some View {
    Section {
      Picker(selection: $model.tool) {
        ForEach(ViewerModel.Tool.allCases, id: \.self) { Text($0.label) }
      } label: {
        Text(.renderKit("Tool"))
      }
      .pickerStyle(.segmented)
      HStack {
        Button(.renderKit("Fit")) { model.zoomToFit() }
        Button {
          model.zoomToActualSize()
        } label: {
          Text(verbatim: "1:1")
        }
        Text(verbatim: Self.percent(100 / model.frame.transform.scale, locale: locale))
          .monospacedDigit()
      }
      Toggle(isOn: $model.frame.clippingOverlay) { Text(.renderKit("Clipping overlay")) }
      HStack {
        Button(.renderKit("Clear region")) { model.clearRegion() }
          .disabled(model.frame.region == nil)
        Button(.renderKit("Clear split")) { model.clearSplit() }
      }
      Text(.renderKit("Hold ⌥ to show the reference.")).font(.caption).foregroundStyle(.secondary)
    } header: {
      Text(.renderKit("View"))
    }
  }

  /// The display stretch: its mode, linking and numbers.
  private var stretchSection: some View {
    Section {
      Picker(selection: $model.stretch) {
        ForEach(ViewerModel.Stretch.allCases, id: \.self) { Text($0.label) }
      } label: {
        Text(.renderKit("Mode"))
      }
      .pickerStyle(.segmented)
      Toggle(isOn: $model.linked) { Text(.renderKit("Linked channels")) }
        .disabled(model.stretch != .auto)
      stretchNumbers
    } header: {
      Text(.renderKit("Display stretch"))
    }
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
        LabeledContent(
          Self.channelName(channel, of: stf.count), value: Self.text(stf[channel], locale: locale)
        )
        .monospacedDigit()
      }
    } else {
      Text(.renderKit("Off: the display is clamp(x).")).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var readout: some View {
    if let readout = model.readout {
      LabeledContent {
        Text(verbatim: "\(readout.x), \(readout.y)")
      } label: {
        Text(.renderKit("Pixel"))
      }
      ForEach(readout.values.indices, id: \.self) { channel in
        LabeledContent(
          Self.channelName(channel, of: readout.values.count),
          value: Self.number(Double(readout.values[channel]), digits: 6, locale: locale))
      }
      if let sky = readout.sky {
        LabeledContent {
          Text(verbatim: LocaleNumber.decimalMark(sky.raText, locale: locale))
        } label: {
          Text(.renderKit("RA"))
        }
        LabeledContent {
          Text(verbatim: sky.decText)
        } label: {
          Text(.renderKit("Dec"))
        }
      }
    } else {
      Text(.renderKit("Move the pointer over the image.")).foregroundStyle(.secondary)
    }
  }

  /// The channel's short name: `K` for a mono image, `R`, `G`, `B` otherwise.
  static func channelName(_ index: Int, of count: Int) -> String {
    count < 3 ? "K" : ["R", "G", "B"][min(index, 2)]
  }

  /// The three STF numbers of a channel.
  static func text(_ stf: STFParameters, locale: Locale) -> String {
    "c0 \(number(stf.shadows, digits: 5, locale: locale))  "
      + "m \(number(stf.midtone, digits: 5, locale: locale))  "
      + "c1 \(number(stf.highlights, digits: 3, locale: locale))"
  }

  /// `value` with `digits` fixed decimals in `locale`.
  static func number(_ value: Double, digits: Int, locale: Locale) -> String {
    LocaleNumber.decimal(
      value, locale: locale, maxFractionDigits: digits, minFractionDigits: digits)
  }

  /// A zoom: `100 %`.
  static func percent(_ value: Double, locale: Locale) -> String {
    number(value, digits: 0, locale: locale) + "\u{a0}%"
  }
}

/// Manual stretch of one channel: the three numbers, each with a slider and its value.
private struct ChannelSliders: View {
  let name: String
  @Binding var parameters: STFParameters
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading) {
      Text(verbatim: name).font(.headline)
      slider(.renderKit("Shadows"), value: $parameters.shadows)
      slider(.renderKit("Midtone"), value: $parameters.midtone)
      slider(.renderKit("Highlights"), value: $parameters.highlights)
    }
  }

  private func slider(_ label: LocalizedStringResource, value: Binding<Double>) -> some View {
    HStack {
      Text(label).frame(width: 72, alignment: .leading)
      Slider(value: value, in: 0...1)
      Text(verbatim: ViewerPanel.number(value.wrappedValue, digits: 5, locale: locale))
        .monospacedDigit().frame(width: 64)
    }
  }
}

extension ViewerModel.Tool {
  /// The segmented control's word.
  var label: LocalizedStringResource {
    switch self {
    case .pan: .renderKit("Pan")
    case .region: .renderKit("Region")
    case .split: .renderKit("Split")
    }
  }
}

extension ViewerModel.Stretch {
  /// The segmented control's word.
  var label: LocalizedStringResource {
    switch self {
    case .auto: .renderKit("Auto")
    case .manual: .renderKit("Manual")
    case .off: .renderKit("Off")
    }
  }
}
