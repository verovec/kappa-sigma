extension Inventory {
  /// The colour verdict of the LIGHTS (`colorModel`): calibration frames follow whichever rig
  /// shot them and do not vote, unless there are no lights at all.
  package var lightColorModel: ColorModel {
    let typed = frames.filter { $0.type != .unknown && $0.type != .video }
    let lights = typed.filter { $0.type == .light }
    let voters = lights.isEmpty ? typed : lights
    let color = voters.count(where: \.isColor)
    if color == 0 { return .mono }
    return color == voters.count ? .osc : .mixed
  }

  /// Clears a BAYERPAT a mono rig's capture program stamped (`clearSpuriousBayer`), PER
  /// INSTRUMENT and only after the pixels were asked: a colour camera behind a clip filter named
  /// `L-eXtreme` keeps its mosaic. A declined probe keeps the old clearing, with a warning.
  package mutating func clearSpuriousBayer(pixels: PixelReader) {
    var byInstrument: [String: [Int]] = [:]
    for (index, frame) in frames.enumerated() {
      byInstrument[frame.instrument, default: []].append(index)
    }
    var cleared = 0
    var declined = 0
    for instrument in byInstrument.keys.sorted() {
      let outcome = clearSpuriousBayer(byInstrument[instrument] ?? [], pixels: pixels)
      cleared += outcome.cleared
      declined += outcome.declined
    }
    if cleared > 0 {
      warnings.append(
        "\(cleared) frame(s) carry a BAYERPAT card but the session uses a filter wheel (mono rig) "
          + "— treating them as monochrome, not one-shot-color")
    }
    if declined > 0 {
      warnings.append(
        "\(declined) frame(s) carry both a BAYERPAT card and a filter name, and their pixels do not "
          + "settle whether the sensor is a colour mosaic — treating them as monochrome, as before. "
          + "If this is a colour camera behind a clip filter, say so with the colour/mono selector")
    }
  }

  private mutating func clearSpuriousBayer(
    _ indices: [Int], pixels: PixelReader
  ) -> (cleared: Int, declined: Int) {
    let wheel = indices.filter { frames[$0].wheelSlot > 0 || Filter.isMono(frames[$0].filter) }
    guard !wheel.isEmpty else { return (0, 0) }
    let bayered = wheel.map { frames[$0] }.filter { !$0.bayer.isEmpty }
    var declined = 0
    if !bayered.isEmpty {
      switch CFAProbe.verdict(bayered, pixels: pixels) {
      case .cfa: return (0, 0)
      case .unknown: declined = bayered.count
      case .mono: break
      }
    }
    var cleared = 0
    for index in indices where !frames[index].bayer.isEmpty {
      let frame = frames[index]
      if frame.wheelSlot > 0 || Filter.isMono(frame.filter) || frame.type.isCalibration {
        frames[index].bayer = ""
        cleared += 1
      }
    }
    return (cleared, declined)
  }

  /// Names unlabeled colour lights `RGB` in an OSC scan, so every channel has a name
  /// (`nameColorChannel`). A mixed scan keeps them unnamed: no single run should stack them.
  package mutating func nameColorChannel() {
    guard colorModel == .osc else { return }
    for index in frames.indices
    where frames[index].type == .light && frames[index].isColor && frames[index].filter.isEmpty {
      frames[index].filter = Filter.color
    }
  }
}
