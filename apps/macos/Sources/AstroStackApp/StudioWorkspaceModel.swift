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
  package internal(set) var isPreviewing = false
  /// The history moved under the open panel: the viewer shows the head, not the panel's values,
  /// until a value moves or Preview is pressed; Apply shows them before it records (R2).
  package internal(set) var isPreviewSuspended = false
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
  /// The last Apply recorded a step that changed nothing: said, so an Undo showing nothing is
  /// understood.
  package internal(set) var appliedNothing = false
  /// The host tool running for the panel (card 0093), with its last line.
  package internal(set) var toolRun: ToolProgress?
  /// What the last host tool reported (a plate solution), in a locale.
  package internal(set) var toolReport: (@Sendable (Locale) -> LocalizedStringResource)?
  /// The host tools by process id: what Apply runs for a `hostTool` process.
  @ObservationIgnored package let tools: [String: StudioTool]
  /// Observed: the history's buttons wait for it (`isMovingHistory`).
  var toolTask: Task<Void, Never>?
  /// Numbers the tool runs, so a late progress line finds its own run or none.
  @ObservationIgnored var toolRunNumber = 0
  /// The head's measured noise, for the denoise's suggestion.
  @ObservationIgnored let headNoise = HeadNoise()
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
  /// What its steps back and forward are registered with on `undoManager` (card 0117).
  @ObservationIgnored let backMoves = StudioMoveTarget()
  @ObservationIgnored let forwardMoves = StudioMoveTarget()
  /// A history button moved the head behind ⌘Z's back since its moves were last dropped: the
  /// next new step drops them all, their chain broken by the redo it discards.
  @ObservationIgnored var movedOutOfBand = false
  @ObservationIgnored private let base: Set<LayerRole>
  @ObservationIgnored var previewTask: Task<Void, Never>?
  /// The head's display statistics: a preview is drawn through them, never through a previous
  /// preview's.
  @ObservationIgnored var headStatistics: [STFMapping] = []
  /// The values and mask of the preview on screen (`nil`: none); see `gridMoved`.
  @ObservationIgnored var shown: (processID: String, params: ParamSet, mask: Mask?)? {
    didSet { gridMoved(from: oldValue.map { ($0.processID, $0.params) }) }
  }
  /// The failure shown is a preview's (the next preview clears it).
  @ObservationIgnored var previewFailed = false

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
    backMoves.workspace = self
    forwardMoves.workspace = self
  }

  /// Marks this workspace replaced (a newer stack opened in the Studio).
  package func retire() {
    isRetired = true
    previewTask?.cancel()
    toolTask?.cancel()
    headNoise.close()
    for target in [self, backMoves, forwardMoves] as [AnyObject] {
      undoManager?.removeAllActions(withTarget: target)
    }
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
    appliedNothing = false
    // A moved preview leaves the screen at once; another stays until the new one replaces it.
    if showsMovedGrid { stopPreview() } else { shown = nil }
    // The defaults are previewed at once: Apply never records what was not shown (R2).
    schedulePreview()
    toolsChosen()
  }

  /// Closes the panel: the viewer shows the head again.
  package func closePanel() {
    panel = nil
    appliedNothing = false
    isPreviewSuspended = false
    hideModel()
    toolReport = nil
    stopPreview()
  }

  func show(_ image: AstroImage, statistics: [STFMapping]? = nil) throws {
    viewer.texture = try Self.texture(image, device: studio.session.device)
    viewer.model.replace(image: image, statistics: statistics)
  }

  func refreshCatalogue() {
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
