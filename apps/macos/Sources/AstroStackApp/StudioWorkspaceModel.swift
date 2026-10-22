package import Foundation
internal import ImageKit
internal import Metal
internal import Observation
package import ProcessKit
package import RenderKit
package import StackKit

/// What the Studio pane drives (card 0087, design §5 B): the catalogue by stage, the panel of
/// the chosen process with its live preview in the viewer, Apply / Undo / Redo on the history,
/// and compare to an earlier step.
@Observable
package final class StudioWorkspaceModel {
  /// A process the catalogue lists.
  package struct Entry: Identifiable, Equatable {
    /// The process id.
    package let id: String
    /// Its catalogue title (ProcessKit's catalog key).
    package let title: String
    /// Why it cannot be the next step, shown on the greyed row (R2: shown, never enforced).
    package let unavailable: StudioUnavailable?
  }

  /// The processes of one stage.
  package struct Group: Identifiable, Equatable {
    /// Linear, non-linear or either.
    package let stage: ProcessStage
    /// Its processes, in registry order.
    package let entries: [Entry]
    package var id: String { stage.rawValue }
  }

  /// The viewer's state, its renderer and the textures it draws.
  package struct Viewer {
    /// The viewer state (zoom, stretch…), kept across heads.
    package let model: ViewerModel
    /// The window's renderer.
    package let renderer: ViewerRenderer
    /// The image shown: the head, or the preview.
    package var texture: ImageTexture
    /// What compare shows: an earlier step.
    package var reference: ImageTexture?
  }

  /// The history and its mirror.
  @ObservationIgnored package let studio: StudioModel
  /// The viewer.
  package internal(set) var viewer: Viewer
  /// The registry by stage.
  package private(set) var catalogue: [Group] = []
  /// The chosen process's panel.
  package private(set) var panel: ProcessPanelModel?
  /// The viewer shows the preview of the panel's values, not the head.
  package private(set) var isPreviewing = false
  /// The step compare shows, if any.
  package internal(set) var comparing: Int?
  /// The viewer shows a geometric preview that moves the pixels (card 0090, `gridMoved`).
  package internal(set) var showsMovedGrid = false
  /// The steps the viewer's head was shown for (`dropRegionIfMoved`).
  @ObservationIgnored var headSteps: [History.Step] = []
  /// Where the process may act (luminosity range, stars), applied by the kit after the
  /// process, to the preview and Apply alike; `nil`: everywhere.
  package var mask: Mask? {
    didSet { if panel != nil { schedulePreview() } }
  }
  /// The pipeline the left column shows (card 0088), set by the window once it is loaded.
  package var pipeline: PipelineSidebarModel?
  /// Why the last action failed.
  package internal(set) var failure: LocalizedStringResource?
  /// The host tool running for the panel (card 0093), with its last line.
  package internal(set) var toolRun: ToolProgress?
  /// What the last host tool reported (a plate solution), in a locale.
  package internal(set) var toolReport: (@Sendable (Locale) -> LocalizedStringResource)?
  /// The host tools by process id: what Apply runs for a `hostTool` process.
  @ObservationIgnored package let tools: [String: StudioTool]
  @ObservationIgnored var toolTask: Task<Void, Never>?
  /// Numbers the tool runs, so a late progress line finds its own run or none.
  @ObservationIgnored var toolRunNumber = 0
  /// Where each host tool stands and the model view (card 0092).
  package internal(set) var batch = BatchState()
  /// Probes a host tool: an engine whose tool is missing is greyed with the reason (card 0092).
  @ObservationIgnored package let locate: @Sendable (HostTool) async -> ToolStatus

  /// The processes it offers.
  @ObservationIgnored package let registry: ProcessRegistry
  /// Replaced by a newer stack's workspace: undo actions registered for it do nothing.
  @ObservationIgnored package private(set) var isRetired = false
  /// Shows the Studio (an undo from another stage brings it into view first).
  @ObservationIgnored package var reveal: () -> Void = {}
  /// The undo manager its moves are registered on, cleared of them when it is retired.
  @ObservationIgnored package weak var undoManager: UndoManager?
  @ObservationIgnored private let base: Set<LayerRole>
  @ObservationIgnored var previewTask: Task<Void, Never>?
  /// The head's display statistics: a preview is drawn through them, never through a previous
  /// preview's.
  @ObservationIgnored private var headStatistics: [STFMapping] = []
  /// The values and mask of the preview on screen (`nil`: none); see `gridMoved`.
  @ObservationIgnored private(set) var shown: (processID: String, params: ParamSet, mask: Mask?)? {
    didSet { gridMoved(from: oldValue.map { ($0.processID, $0.params) }) }
  }
  /// The failure shown is a preview's (the next preview clears it).
  @ObservationIgnored private var previewFailed = false

  /// The workspace of `studio` whose bundle holds the layer roles `base`.
  package init(
    studio: StudioModel, base: Set<LayerRole>, tools: [String: StudioTool] = [:],
    locate: @escaping @Sendable (HostTool) async -> ToolStatus = HostTools.live().locate
  ) throws {
    self.studio = studio
    self.tools = tools
    self.locate = locate
    self.base = base
    registry = studio.session.registry
    let renderer = try ViewerRenderer(device: studio.session.device)
    viewer = Viewer(
      model: ViewerModel(image: studio.head), renderer: renderer,
      texture: try Self.texture(studio.head, device: studio.session.device))
    refreshCatalogue()
    headStatistics = viewer.model.statistics
    watchDisplayStretch()
    headSteps = studio.steps
  }

  /// Marks this workspace replaced (a newer stack opened in the Studio).
  package func retire() {
    isRetired = true
    previewTask?.cancel()
    toolTask?.cancel()
    undoManager?.removeAllActions(withTarget: self)
  }

  /// Opens the panel of `processID` at `params` (its defaults when `nil`), with its suggestions.
  package func choose(_ processID: String, params: ParamSet? = nil) {
    guard let type = registry.type(id: processID) else { return }
    let panel = ProcessPanelModel(type: type, params: params ?? ParamSet(schema: type.schema))
    refresh(panel)
    panel.onChange = { [weak self] in self?.panelChanged() }
    hideModel()
    self.panel = panel
    toolReport = nil
    // A moved preview leaves the screen at once; another stays until the new one replaces it.
    if showsMovedGrid { stopPreview() } else { shown = nil }
    // The defaults are previewed at once: Apply never records what was not shown (R2).
    schedulePreview()
    toolsChosen()
  }

  /// Closes the panel: the viewer shows the head again.
  package func closePanel() {
    panel = nil
    hideModel()
    toolReport = nil
    stopPreview()
  }

  /// Renders the panel's values now (the debounced preview calls it one frame after a change).
  package func previewNow() async {
    drawPreview()
  }

  /// Draws the panel's values on the head now; a failure shows the head, never an older preview.
  private func drawPreview() {
    guard let panel else { return }
    do {
      let preview = try studio.preview(panel.type.id, params: panel.params, mask: maskImage())
      // Through the head's display stretch: an auto-stretch fitted to the preview would hide
      // the very change the process makes (what is shown is what Apply records, R2).
      let same = preview.planes.count == headStatistics.count
      willShow(panel.type.id, panel.params)
      try show(preview, statistics: same ? headStatistics : nil)
      isPreviewing = true
      shown = (panel.type.id, panel.params, mask)
      // A preview clears only a preview's failure: an Apply or Undo failure stays in view.
      if previewFailed { failure = nil }
      previewFailed = false
    } catch {
      shown = nil
      failure = UserFacingError(error).message
      previewFailed = true
      if isPreviewing {
        isPreviewing = false
        try? show(studio.head, statistics: headStatistics)
      }
    }
  }

  /// Applies the panel's values at full resolution: the head moves (a failure is shown).
  package func apply() throws {
    guard let panel else { return }
    // Apply records what the viewer shows (R2): values not drawn yet (a value just typed, a
    // drag within the frame) are drawn first, and what was drawn is what is recorded.
    previewTask?.cancel()
    if !isShowing(panel) { drawPreview() }
    guard isShowing(panel) else { return }
    var used: AstroImage?
    try reported {
      used = try maskImage()
      try studio.apply(panel.type.id, params: panel.params, mask: used)
    }
    // The user's manual work becomes the recipe (R5): the pipeline records the step.
    pipeline?.applied(panel.type.id, params: panel.params, masked: used != nil)
  }

  /// Whether the viewer shows the current values and mask of `panel`.
  private func isShowing(_ panel: ProcessPanelModel) -> Bool {
    guard let shown else { return false }
    return shown.processID == panel.type.id && shown.params == panel.params && shown.mask == mask
  }

  /// Back one step.
  package func undo() throws {
    try reported { try studio.undo() }
  }

  /// Forward one undone step.
  package func redo() throws {
    try reported { try studio.redo() }
  }

  /// Runs a history move, then shows the head; a failure is shown in the panel and rethrown.
  func reported(_ move: () throws -> Void) throws {
    do {
      try move()
      failure = nil
      previewFailed = false
    } catch {
      failure = UserFacingError(error).message
      previewFailed = false
      try? headChanged()
      throw error
    }
    do {
      try headChanged()
    } catch {
      // The history moved but its head could not be shown: say so, never a silent stale view.
      failure = UserFacingError(error).message
      throw error
    }
  }

  /// A value moved: the suggestions follow the values they depend on, the preview follows.
  private func panelChanged() {
    if let panel { panel.suggestions = offers(for: panel.type, params: panel.params) }
    greyUnavailable()
    // The head comes back now: a preview cancelled or refused would leave the model on screen.
    hideModel()
    schedulePreview()
  }

  private func schedulePreview() {
    previewTask?.cancel()
    previewTask = Task { [weak self] in
      // One frame: a slider drag renders its last position, not every intermediate one.
      try? await Task.sleep(for: .milliseconds(16))
      guard !Task.isCancelled else { return }
      await self?.previewNow()
    }
  }

  private func stopPreview() {
    previewTask?.cancel()
    shown = nil
    guard isPreviewing else { return }
    isPreviewing = false
    try? show(studio.head)
  }

  /// The history moved (an Apply, an undo, a pipeline run): the viewer, the panel's inputs and
  /// the catalogue follow the new head.
  func headChanged() throws {
    dropRegionIfMoved()
    shown = nil
    // A report speaks of the head it was made on.
    toolReport = nil
    batch.showsModel = false
    defer { headStatistics = viewer.model.statistics }
    isPreviewing = false
    // A compared step undone, or off the head's grid (a crop applied), stops the compare.
    if let comparing, !onHeadGrid(step: comparing) {
      try compare(toStep: nil)
    }
    try show(studio.head)
    // After the viewer shows the new head: the display stretch offered is the one on screen.
    if let panel { refresh(panel) }
    refreshCatalogue()
    // The panel stays open on the new head: its values are previewed on it again (R2).
    if panel != nil { schedulePreview() }
  }

  func show(_ image: AstroImage, statistics: [STFMapping]? = nil) throws {
    viewer.texture = try Self.texture(image, device: studio.session.device)
    viewer.model.replace(image: image, statistics: statistics)
  }

  private func refreshCatalogue() {
    var groups: [Group] = []
    for stage in [ProcessStage.linear, .any, .nonlinear] {
      let entries = registry.types.filter { $0.stage == stage }.map { type in
        Entry(
          id: type.id, title: type.title,
          unavailable: studio.session.unavailable(for: type, base: base, registry: registry)
            ?? (type.hostTool && tools[type.id] == nil ? .toolMissing : nil))
      }
      if !entries.isEmpty { groups.append(Group(stage: stage, entries: entries)) }
    }
    catalogue = groups
  }

  static func texture(_ image: AstroImage, device: MTLDevice) throws -> ImageTexture {
    try ImageTexture(device: device, width: image.width, height: image.height, planes: image.planes)
  }
}
