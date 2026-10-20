/// `Fixtures/finish/manifest.json`: what `scripts/record-finish-oracle.sh` recorded, how, and the
/// hash and size of every file (paths relative to `~/Documents/astro/fixtures/finish`).
package struct FinishManifest: Codable, Equatable, Sendable {
  /// Where the recording comes from.
  package struct Provenance: Codable, Equatable, Sendable {
    /// The run folder under `~/Documents/astro/runs`.
    package let run: String
    /// The legacy job number.
    package let runNumber: Int
    /// The day it was recorded.
    package let recorded: String
    /// The chain, in words ("v9 HaPlus: hdrcomp → astrocomp → starnet2 → stardesat").
    package let chain: String
    /// Tool versions (`go`, `siril`, `starnet2`).
    package let versions: [String: String]
    /// The copied tool sources and their hashes.
    package let tools: [File]
  }

  /// The centre crop, in the run's pixel coordinates.
  package struct Crop: Codable, Equatable, Sendable {
    /// Left column.
    package let x: Int
    /// Bottom row (Siril's origin).
    package let y: Int
    /// Width.
    package let width: Int
    /// Height.
    package let height: Int

    /// A crop rectangle.
    package init(x: Int, y: Int, width: Int, height: Int) {
      self.x = x
      self.y = y
      self.width = width
      self.height = height
    }
  }

  /// One step of the chain, on the full frame and on the crop.
  package struct Stage: Codable, Equatable, Sendable {
    /// `screens_only`, `hdr_only`, `haplus_full`, `starless`, `stars_25`…
    package let name: String
    /// The tool run.
    package let tool: String
    /// Its arguments, exactly (flags; positional ones for stardesat).
    package let flags: [String]
    /// The stage's inputs (layer or earlier stage file names).
    package let inputs: [String]
    /// Its outputs: `full/<name>.*` and `crop/<name>.*`.
    package let outputs: [File]
  }

  /// One recorded file.
  package struct File: Codable, Equatable, Sendable {
    /// Relative to the finish folder.
    package let path: String
    /// Hex SHA-256.
    package let sha256: String
    /// Pixels (0 for a source file).
    package let width: Int
    /// Pixels (0 for a source file).
    package let height: Int

    /// A recorded file.
    package init(path: String, sha256: String, width: Int, height: Int) {
      self.path = path
      self.sha256 = sha256
      self.width = width
      self.height = height
    }

    /// `full` or `crop`: the first path component.
    package var variant: String {
      String(path.split(separator: "/").first ?? "")
    }
  }

  /// Where it comes from.
  package let provenance: Provenance
  /// The crop rectangle.
  package let crop: Crop
  /// The cropped input layers (`crop/rgb_base.fits`, `crop/syn_Ha.fits`, `crop/syn_OIII.fits`).
  package let layers: [File]
  /// The chain's stages, in order.
  package let stages: [Stage]

  /// Every image file the manifest pins (layers and stage outputs).
  package var allFiles: [File] {
    layers + stages.flatMap(\.outputs)
  }
}
