package import Foundation
internal import ImageKit
internal import Metal
internal import Observation
package import ProcessKit
package import RenderKit

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
  package private(set) var viewer: Viewer
  /// The registry by stage.
  package private(set) var catalogue: [Group] = []
  /// The chosen process's panel.
  package private(set) var panel: ProcessPanelModel?
  /// The viewer shows the preview of the panel's values, not the head.
  package private(set) var isPreviewing = false
  /// The step compare shows, if any.
  package private(set) var comparing: Int?
  /// Where the process may act (luminosity range, stars), applied by the kit after the
  /// process, to the preview and Apply alike; `nil`: everywhere.
  package var mask: Mask? {
    didSet { if panel != nil { schedulePreview() } }
  }
  /// Why the last action failed.
  package private(set) var failure: LocalizedStringResource?

  /// The processes it offers.
  @ObservationIgnored package let registry: ProcessRegistry
  /// Replaced by a newer stack's workspace: undo actions registered for it do nothing.
  @ObservationIgnored package private(set) var isRetired = false
  /// Shows the Studio (an undo from another stage brings it into view first).
  @ObservationIgnored package var reveal: () -> Void = {}
  /// The undo manager its moves are registered on, cleared of them when it is retired.
  @ObservationIgnored package weak var undoManager: UndoManager?
  @ObservationIgnored private let base: Set<LayerRole>
  @ObservationIgnored private var previewTask: Task<Void, Never>?
  /// The head's display statistics: a preview is drawn through them, never a previous one's.
  @ObservationIgnored private var headStatistics: [STFMapping] = []
  /// The values and mask of the preview on screen (`nil`: none); see `gridMoved`.
  private(set) var shown: (processID: String, params: ParamSet, mask: Mask?)? {
    didSet { gridMoved(from: oldValue.map { ($0.processID, $0.params) }) }
  }
  /// The failure shown is a preview's (the next preview clears it).
  @ObservationIgnored private var previewFailed = false

  /// The workspace of `studio` whose bundle holds the layer roles `base`.
  package init(studio: StudioModel, base: Set<LayerRole>) throws {
    self.studio = studio
    self.base = base
    registry = studio.session.registry
    let renderer = try ViewerRenderer(device: studio.session.device)
    viewer = Viewer(
      model: ViewerModel(image: studio.head), renderer: renderer,
      texture: try Self.texture(studio.head, device: studio.session.device))
    refreshCatalogue()
    headStatistics = viewer.model.statistics
    watchDisplayStretch()
  }

  /// Marks this workspace replaced (a newer stack opened in the Studio).
  package func retire() {
    isRetired = true
    previewTask?.cancel()
    undoManager?.removeAllActions(withTarget: self)
  }

  /// The catalogue title of process `id` (ProcessKit's catalog key), or the id.
  package func title(of id: String) -> String {
    registry.type(id: id)?.title ?? id
  }

  /// Opens the panel of `processID` at its defaults, with its suggestions.
  package func choose(_ processID: String) {
    guard let type = registry.type(id: processID) else { return }
    let panel = ProcessPanelModel(type: type, params: ParamSet(schema: type.schema))
    refresh(panel)
    panel.onChange = { [weak self] in self?.panelChanged() }
    self.panel = panel
    stopPreview()
    // The defaults are previewed at once: Apply never records what was not shown (R2).
    schedulePreview()
  }

  /// Closes the panel: the viewer shows the head again.
  package func closePanel() {
    panel = nil
    stopPreview()
  }

  /// Renders the panel's values now (the debounced preview calls it one frame after a change).
  package func previewNow() async {
    drawPreview()
  }

  /// Draws the panel's values on the head now; a failure shows the head again (never an older
  /// preview standing for the current values).
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

  /// Applies the panel's values at full resolution: the head moves.
  ///
  /// A failure is shown in the panel.
  package func apply() throws {
    guard let panel else { return }
    // Apply records what the viewer shows (R2): values not drawn yet (a value just typed, a
    // drag within the frame) are drawn first, and what was drawn is what is recorded.
    previewTask?.cancel()
    if !isShowing(panel) { drawPreview() }
    guard isShowing(panel) else { return }
    try reported { try studio.apply(panel.type.id, params: panel.params, mask: maskImage()) }
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
  private func reported(_ move: () throws -> Void) throws {
    let before = studio.steps
    defer { dropRegionIfMoved(since: before) }
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

  /// Compares the viewer's image with the output of step `index` (`nil`: no compare).
  package func compare(toStep index: Int?) throws {
    guard let index else {
      viewer.reference = nil
      comparing = nil
      return
    }
    // On a moved preview (a crop, a flip) the step's pixels are not under the ones shown.
    guard !showsMovedGrid else { throw UserFacingError.movedPreview }
    let image = try studio.session.history.output(ofStep: index)
    // A step of another size (before a crop or a quarter turn) does not lie on the head's grid.
    guard image.width == studio.head.width, image.height == studio.head.height else {
      throw StudioError.otherSize(step: index)
    }
    viewer.reference = try Self.texture(image, device: studio.session.device)
    comparing = index
  }

  /// A value moved: the suggestions follow the values they depend on, the preview follows.
  private func panelChanged() {
    if let panel { panel.suggestions = offers(for: panel.type, params: panel.params) }
    schedulePreview()
  }

  /// Compares with step `index`, or stops when it is the one compared; a step whose output
  /// cannot be read is reported.
  package func toggleCompare(_ index: Int) {
    do {
      try compare(toStep: comparing == index ? nil : index)
    } catch {
      failure = UserFacingError(error).message
    }
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

  private func headChanged() throws {
    shown = nil
    defer { headStatistics = viewer.model.statistics }
    isPreviewing = false
    // A compared step undone, or off the head's grid (a crop applied), stops the compare.
    if let comparing, comparing >= studio.steps.count || !fitsHead(step: comparing) {
      try compare(toStep: nil)
    }
    try show(studio.head)
    // After the viewer shows the new head: the display stretch offered is the one on screen.
    if let panel { refresh(panel) }
    refreshCatalogue()
    // The panel stays open on the new head: its values are previewed on it again (R2).
    if panel != nil { schedulePreview() }
  }

  private func show(_ image: AstroImage, statistics: [STFMapping]? = nil) throws {
    viewer.texture = try Self.texture(image, device: studio.session.device)
    viewer.model.replace(image: image, statistics: statistics)
  }

  private func refreshCatalogue() {
    var groups: [Group] = []
    for stage in [ProcessStage.linear, .any, .nonlinear] {
      let entries = registry.types.filter { $0.stage == stage }.map { type in
        Entry(
          id: type.id, title: type.title,
          unavailable: studio.session.unavailable(for: type, base: base, registry: registry))
      }
      if !entries.isEmpty { groups.append(Group(stage: stage, entries: entries)) }
    }
    catalogue = groups
  }

  private static func texture(_ image: AstroImage, device: MTLDevice) throws -> ImageTexture {
    try ImageTexture(device: device, width: image.width, height: image.height, planes: image.planes)
  }
}
