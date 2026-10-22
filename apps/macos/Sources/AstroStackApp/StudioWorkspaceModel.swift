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
    package let unavailableReason: String?
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
  /// Why the last action failed.
  package private(set) var failure: LocalizedStringResource?

  @ObservationIgnored private let registry: ProcessRegistry
  @ObservationIgnored private let base: Set<LayerRole>
  @ObservationIgnored private var previewTask: Task<Void, Never>?

  /// The workspace of `studio` whose bundle holds the layer roles `base`.
  package init(studio: StudioModel, base: Set<LayerRole>) throws {
    self.studio = studio
    self.base = base
    registry = try ProcessRegistry.standard()
    let renderer = try ViewerRenderer(device: studio.session.device)
    viewer = Viewer(
      model: ViewerModel(image: studio.head), renderer: renderer,
      texture: try Self.texture(studio.head, device: studio.session.device))
    try refreshCatalogue()
  }

  /// Opens the panel of `processID` at its defaults, with its suggestions.
  package func choose(_ processID: String) {
    guard let type = registry.type(id: processID) else { return }
    let params = ParamSet(schema: type.schema)
    let suggestions = (try? studio.session.suggestions(for: type, params: params)) ?? []
    let panel = ProcessPanelModel(type: type, params: params, suggestions: suggestions)
    panel.onChange = { [weak self] in self?.schedulePreview() }
    self.panel = panel
    stopPreview()
  }

  /// Closes the panel: the viewer shows the head again.
  package func closePanel() {
    panel = nil
    stopPreview()
  }

  /// Renders the panel's values now (the debounced preview calls it one frame after a change).
  package func previewNow() async {
    guard let panel else { return }
    do {
      let preview = try studio.preview(panel.type.id, params: panel.params)
      try show(preview)
      isPreviewing = true
      failure = nil
    } catch {
      failure = UserFacingError(error).message
    }
  }

  /// Applies the panel's values at full resolution: the head moves.
  package func apply() throws {
    guard let panel else { return }
    previewTask?.cancel()
    try studio.apply(panel.type.id, params: panel.params)
    try headChanged()
  }

  /// Back one step.
  package func undo() throws {
    try studio.undo()
    try headChanged()
  }

  /// Forward one undone step.
  package func redo() throws {
    try studio.redo()
    try headChanged()
  }

  /// Compares the viewer's image with the output of step `index` (`nil`: no compare).
  package func compare(toStep index: Int?) throws {
    guard let index else {
      viewer.reference = nil
      comparing = nil
      return
    }
    let image = try studio.session.history.output(ofStep: index)
    viewer.reference = try Self.texture(image, device: studio.session.device)
    comparing = index
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
    guard isPreviewing else { return }
    isPreviewing = false
    try? show(studio.head)
  }

  private func headChanged() throws {
    isPreviewing = false
    try show(studio.head)
    try refreshCatalogue()
  }

  private func show(_ image: AstroImage) throws {
    viewer.texture = try Self.texture(image, device: studio.session.device)
    viewer.model.replace(image: image)
  }

  private func refreshCatalogue() throws {
    var groups: [Group] = []
    for stage in [ProcessStage.linear, .any, .nonlinear] {
      let entries = try registry.types.filter { $0.stage == stage }.map { type in
        Entry(
          id: type.id, title: type.title,
          unavailableReason: try studio.session.unavailableReason(
            for: type, base: base, registry: registry))
      }
      if !entries.isEmpty { groups.append(Group(stage: stage, entries: entries)) }
    }
    catalogue = groups
  }

  private static func texture(_ image: AstroImage, device: MTLDevice) throws -> ImageTexture {
    try ImageTexture(device: device, width: image.width, height: image.height, planes: image.planes)
  }
}
