/// The one namespace of accessibility identifiers (card 0079): stable ids a test, a UI script or
/// 0061's first-stack guide resolves a control by.
///
/// Never derived from a title (titles change with the language): every id is built here from a
/// fixed name and, for a repeated control, the caller's stable key.
nonisolated package struct AccessibilityID: Hashable, Sendable, CustomStringConvertible {
  /// The identifier string (`fr.astrostack.parameter.haBlend.slider`).
  package let rawValue: String

  private init(_ path: String...) {
    rawValue = (["fr.astrostack"] + path).joined(separator: ".")
  }

  package var description: String { rawValue }

  /// A control inside a shared component.
  package enum Part: String, Sendable {
    /// Back to the default.
    case reset
    /// The slider of a parameter.
    case slider
    /// The typed field of a parameter.
    case field
    /// A tool's install link.
    case install
    /// A tool's « Re-check ».
    case recheck
    /// A curve's drawing surface.
    case canvas
    /// The « ? » beside a parameter (card 0086).
    case help
    /// A flag parameter's toggle (card 0087).
    case toggle
    /// A choice parameter's menu (card 0087).
    case choice
    /// A process's suggested value, applied on click only (card 0087).
    case suggestion
  }

  // MARK: - Shared components

  /// A parameter row's `part` (`slider`, `field`, `reset`) for the parameter `key`.
  package static func parameter(_ key: String, _ part: Part) -> Self {
    Self("parameter", key, part.rawValue)
  }

  /// An install card's `part` (`install`, `recheck`) for `tool`.
  package static func installCard(_ tool: String, _ part: Part) -> Self {
    Self("install", tool.lowercased(), part.rawValue)
  }

  /// A curve editor's `part` (`canvas`, `reset`) for the curve `key`.
  package static func curve(_ key: String, _ part: Part) -> Self {
    Self("curve", key, part.rawValue)
  }

  /// A help button (card 0086) on `key`: a stage, a profile value, a process card.
  package static func help(_ key: String) -> Self {
    Self("help", key)
  }

  /// A histogram's `part` (`canvas`) for the plot `key` (card 0085).
  package static func histogram(_ key: String, _ part: Part) -> Self {
    Self("histogram", key, part.rawValue)
  }

  // MARK: - Viewer

  /// The viewer panel's control `name` (`resetAuto`, `histogramDomain`; card 0085).
  package static func viewer(_ name: String) -> Self {
    Self("viewer", name)
  }

  // MARK: - Workspace

  /// The journey sidebar row of a stage (`JourneyStage.rawValue`).
  package static func journeyStage(_ stage: String) -> Self {
    Self("journey", stage)
  }

  /// A stage pane's control `name` in `stage`.
  package static func stageControl(_ stage: String, _ name: String) -> Self {
    Self("stage", stage, name)
  }

  /// The Données stage's « Import Captures… ».
  package static let importCaptures = stageControl("data", "import")

  /// The Données stage's « Rescan » (0078).
  package static let dataRescan = stageControl("data", "rescan")

  /// The Données stage's « Cancel » of a Rescan in flight (0078).
  package static let dataCancelScan = stageControl("data", "cancelScan")

  /// The Données stage's « Open Calibration » above the coverage (0078).
  package static let dataOpenCalibration = stageControl("data", "openCalibration")

  /// The Calibration stage's « Rescan ».
  package static let calibrationRescan = stageControl("calibration", "rescan")

  /// The Calibration stage's « Cancel » of a Rescan in flight.
  package static let calibrationCancelScan = stageControl("calibration", "cancelScan")

  /// The Calibration stage's « Preview » of the master a cell applies, by its `calib_exclude`
  /// token.
  package static func calibrationPreview(_ suggestionID: String) -> Self {
    stageControl("calibration", "preview." + suggestionID)
  }

  /// The Empilement stage's « Save… » of an untitled project.
  package static let stackingSave = stageControl("stacking", "save")

  /// The Empilement stage's preset picker.
  package static let stackingPreset = stageControl("stacking", "preset")

  /// The Empilement stage's « Run ».
  package static let stackingRun = stageControl("stacking", "run")

  /// The Empilement stage's « Cancel ».
  package static let stackingCancel = stageControl("stacking", "cancel")
  /// A flag or choice knob of the Stacking panel, by its glossary term id (card 0070).
  package static func stackingKnob(_ termID: String) -> Self { stageControl("stacking", termID) }

  /// The Stacking panel's Reset All (card 0070).
  package static let stackingResetKnobs = stageControl("stacking", "resetKnobs")

  /// The Tri stage's « Review frames before stacking » toggle (card 0069).
  package static let reviewToggle = stageControl("review", "toggle")

  /// The Tri stage's lane picker, when a run had several lanes.
  package static let reviewLane = stageControl("review", "lane")

  /// The Tri stage's « Continue » (card 0069).
  package static let reviewContinue = stageControl("review", "continue")

  /// The Tri stage's blink arrow to the previous frame.
  package static let reviewBlinkPrevious = stageControl("review", "blink.previous")

  /// The Tri stage's blink arrow to the next frame.
  package static let reviewBlinkNext = stageControl("review", "blink.next")

  /// The Tri stage's keep / reject toggle of frame `index`.
  package static func reviewKeep(_ index: Int) -> Self {
    stageControl("review", "keep.\(index)")
  }

  /// The Tri stage's « Keep » of frame `index` in the blink panel (the table has the toggle).
  package static func reviewBlinkKeep(_ index: Int) -> Self {
    stageControl("review", "blink.keep.\(index)")
  }

  /// The Tri stage's « Reject » of frame `index` in the blink panel.
  package static func reviewBlinkReject(_ index: Int) -> Self {
    stageControl("review", "blink.reject.\(index)")
  }

  /// The Tri stage's metric picker over the histogram.
  package static let reviewMetric = stageControl("review", "metric")

  /// The Tri stage's « Choose the reference frame » toggle (card 0096).
  package static let referenceToggle = stageControl("review", "referenceToggle")

  /// The Tri stage's « reference » radio of frame `index` at a reference pause (card 0096).
  package static func reviewReference(_ index: Int) -> Self {
    stageControl("review", "reference.\(index)")
  }

  /// A process panel's « Advanced » switch (card 0087).
  package static func processAdvanced(_ processID: String) -> Self {
    parameter(processID + ".advanced", .toggle)
  }

  /// A process of the Studio's catalogue (card 0087).
  package static func studioProcess(_ processID: String) -> Self {
    stageControl("studio", "process." + processID)
  }

  /// A step of the Studio's history list: compare to it (card 0087).
  package static func studioStep(_ index: Int) -> Self {
    stageControl("studio", "step." + String(index))
  }

  /// The parameter key of the Studio mask's value `name` (`ParameterRow(…, key:)`, card 0087).
  package static func studioMaskKey(_ name: String) -> String {
    "studio.mask." + name
  }

  /// The Studio's mask source menu (card 0087).
  package static let studioMaskSource = stageControl("studio", "mask.source")

  /// The Studio's mask « Invert » (card 0087).
  package static let studioMaskInvert = stageControl("studio", "mask.invert")

  /// The Studio's « Apply » (card 0087).
  package static let studioApply = stageControl("studio", "apply")

  /// The Studio's « Undo » (card 0087).
  package static let studioUndo = stageControl("studio", "undo")

  /// The Studio's « Redo » (card 0087).
  package static let studioRedo = stageControl("studio", "redo")

  /// The Studio's « Close » of the process panel (card 0087).
  package static let studioClosePanel = stageControl("studio", "closePanel")

  /// The Import sheet's profile picker (card 0060).
  package static let importProfile = Self("import", "profile")

  /// The shortcuts sheet's search field.
  package static let shortcutsSearch = Self("shortcuts", "search")

  /// The glossary window's search field.
  package static let glossarySearch = Self("glossary", "search")

  /// A first-stack guide button (`back`, `next`, `close`; card 0061).
  package static func guide(_ name: String) -> Self {
    Self("guide", name)
  }

  /// An id for a test fixture only (`fr.astrostack.test.<name>`).
  package static func fixture(_ name: String) -> Self {
    Self("test", name)
  }
}
