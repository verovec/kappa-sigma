internal import Foundation

/// What a legacy run's `run.json` and `stages.json` say that opening it needs.
struct LegacyRunRecord {
  /// A stacked channel: its filter and frame count.
  struct Channel: Decodable {
    let filter: String
    let stackedFrames: Int?

    enum CodingKeys: String, CodingKey {
      case filter
      case stackedFrames = "stacked_frames"
    }
  }

  private struct Run: Decodable {
    let object: String
    let runID: String
    let channels: [Channel]?

    enum CodingKeys: String, CodingKey {
      case object, channels
      case runID = "run_id"
    }
  }

  private struct Stages: Decodable {
    let preset: StagesPreset?
  }

  /// The preset fields of `stages.json` that opening a run needs.
  private struct StagesPreset: Decodable {
    let color: String?

    enum CodingKeys: String, CodingKey { case color = "Color" }
  }

  let object: String
  let runID: String
  let colorModel: ColorModel
  /// Channel filter → frames stacked.
  let frames: [String: Int]

  /// Reads `folder/run.json` (required) and `folder/stages.json` (optional).
  static func read(_ folder: URL) throws -> Self {
    let run: Run
    do {
      run = try JSONDecoder().decode(
        Run.self, from: Data(contentsOf: folder.appendingPathComponent("run.json")))
    } catch {
      throw LegacyRunError.notARun(folder.path)
    }
    let stages = try? JSONDecoder().decode(
      Stages.self, from: Data(contentsOf: folder.appendingPathComponent("stages.json")))
    let color = stages?.preset?.color.flatMap { ColorModel(rawValue: $0.lowercased()) } ?? .osc
    var frames: [String: Int] = [:]
    // Keyed like the layer files: an unfiltered channel ("") is the `mono` tag.
    for channel in run.channels ?? [] {
      if let count = channel.stackedFrames { frames[ChannelTag.of(channel.filter)] = count }
    }
    return Self(object: run.object, runID: run.runID, colorModel: color, frames: frames)
  }

  /// Frames of layer `id` from `source`: the base counts the colour channel, a `syn_*` line the
  /// dual-band channel it was split from, anything else its own channel.
  func frames(for id: String, source: String) -> Int? {
    Self.frames(for: id, source: source, in: frames)
  }

  static func frames(for id: String, source: String, in frames: [String: Int]) -> Int? {
    if source == "syn" {
      // Several dual-band channels: the first by name, the same on every launch.
      let dualBand = frames.keys.filter(LegacyLayerDiscovery.isDualBand).sorted()
      return dualBand.first.flatMap { frames[$0] }
    }
    return frames[id]
  }
}
