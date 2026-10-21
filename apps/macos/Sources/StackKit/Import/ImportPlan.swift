/// What the Import sheet shows before any run (`/api/inspect` + `/api/calib/preview`): the scan
/// grouped by night and the calibration every light set would get, gaps included.
///
/// Everything here is read off `Inventory` and `CalibrationPreview`; the plan adds no heuristic.
package struct ImportPlan: Equatable, Sendable {
  /// One frame set as a table row.
  package struct SetRow: Equatable, Sendable, Identifiable {
    package var key: SetKey
    package var count: Int
    /// The clip filter of a colour light set (`unknown` elsewhere, or undecided).
    package var filterSet: FilterSet
    /// The set id overrides are stored under.
    package var id: String { key.id }
    package var type: FrameType { key.type }
    package var filter: String { key.filter }

    /// The row of `set`.
    package init(_ set: FrameSet) {
      key = set.key
      count = set.count
      filterSet = set.filterSet
    }
  }

  /// The sets of one capture night; `""` holds the darks and bias every night shares, and
  /// undated frames.
  package struct Night: Equatable, Sendable, Identifiable {
    package var session: String
    package var sets: [SetRow]
    package var id: String { session }
  }

  /// What a role of a light set would get.
  package indirect enum Status: Equatable, Sendable {
    /// A library master, used as is.
    case library(path: String, frames: Int)
    /// A master the run builds from the capture's own frames.
    case build(frames: Int)
    /// Unchecked by the user: what was proposed.
    case excluded(Self)
    /// Nothing matches; the channel's notes say why.
    case missing
  }

  /// One role (dark, flat, bias) of a light set.
  package struct Cell: Equatable, Sendable, Identifiable {
    package var role: CalibrationRole
    /// The `calib_exclude` token of this cell.
    package var suggestionID: String
    package var status: Status
    /// The master applied, or the one the user excluded; `nil` for a gap.
    package var master: CalibrationMaster?
    package var id: String { suggestionID }
  }

  /// A light set and its calibration.
  package struct Channel: Equatable, Sendable, Identifiable {
    package var key: SetKey
    /// Dark, flat, bias, in that order.
    package var cells: [Cell]
    /// The matcher's explanation of every fallback and gap.
    package var notes: [String]
    package var filter: String { key.filter }
    package var id: String { key.id }
    /// A role with nothing to apply that the user did not ask to skip.
    package var hasGap: Bool { cells.contains { $0.status == .missing } }
  }

  /// The scan the plan describes, kept for the run (0057).
  package var inventory: Inventory
  /// The library masters it was matched against, kept to replan without rescanning.
  package var library: [CalibrationMaster]
  package var nights: [Night]
  package var calibration: [Channel]
  package var warnings: [String] { inventory.warnings }

  /// The plan of `inventory`, matched against `library` plus what the capture would build.
  package init(inventory: Inventory, library: [CalibrationMaster], request: ImportRequest) {
    self.inventory = inventory
    self.library = library
    nights = Self.nights(inventory)
    let candidates = CalibrationPreview.candidates(inventory: inventory, library: library)
    let proposed = CalibrationPreview(
      inventory: inventory, masters: candidates, force: request.forceCalibration)
    let applied = CalibrationPreview(
      inventory: inventory, masters: candidates, excluded: request.calibExclude,
      force: request.forceCalibration)
    calibration = zip(proposed.channels, applied.channels).map { proposal, choice in
      Channel(
        key: choice.key,
        cells: CalibrationRole.allCases.map { role in
          Self.cell(
            role, light: choice.key, proposed: proposal, applied: choice,
            excluded: request.calibExclude)
        },
        notes: choice.notes)
    }
  }

  private static func cell(
    _ role: CalibrationRole, light: SetKey, proposed: CalibrationPreview.Channel,
    applied: CalibrationPreview.Channel, excluded: [String]
  ) -> Cell {
    let id = CalibrationMatcher.suggestionID(light, role: role)
    if let suggestion = applied.suggestions.first(where: { $0.role == role }) {
      return Cell(
        role: role, suggestionID: id, status: Self.status(suggestion), master: suggestion.master)
    }
    if excluded.contains(id),
      let suggestion = proposed.suggestions.first(where: { $0.role == role })
    {
      return Cell(
        role: role, suggestionID: id, status: .excluded(Self.status(suggestion)),
        master: suggestion.master)
    }
    // Dropped as a consequence (a -opt dark without its bias): a gap, explained by the notes.
    return Cell(role: role, suggestionID: id, status: .missing)
  }

  private static func status(_ suggestion: CalibrationPreview.Suggestion) -> Status {
    suggestion.fromCapture
      ? .build(frames: suggestion.master.frameCount)
      : .library(path: suggestion.master.path, frames: suggestion.master.frameCount)
  }

  /// Lights and flats under their night (the key's, else their frames' on a one-night scan),
  /// dated nights in order, then the shared calibration.
  private static func nights(_ inventory: Inventory) -> [Night] {
    var order: [String] = []
    var rows: [String: [SetRow]] = [:]
    for set in inventory.sets {
      let night = [.light, .flat].contains(set.key.type) ? Self.night(of: set) : ""
      if rows[night] == nil { order.append(night) }
      rows[night, default: []].append(SetRow(set))
    }
    let sorted = order.filter { !$0.isEmpty }.sorted() + (order.contains("") ? [""] : [])
    return sorted.map { Night(session: $0, sets: rows[$0] ?? []) }
  }

  /// The night of a set: its key's, else its dated frames' (a one-night scan keeps no night in
  /// its keys, so they share one); `""` when no frame is dated.
  package static func night(of set: FrameSet) -> String {
    set.key.session.isEmpty
      ? set.frames.first { !$0.session.isEmpty }?.session ?? "" : set.key.session
  }
}
