package import Foundation
internal import Observation
package import ProjectKit
package import StackKit

/// The state of a project window: the journey stage shown and every stage's status, the
/// sources, the Import sheet when one is open, the preprocessing run and the stack in the Studio.
@Observable
package final class ProjectWindowModel {
  /// The stage the user chose, restored per project; only `select` changes it.
  package private(set) var selection = JourneyStage.data
  /// Every stage's status, derived from the project on each refresh.
  package private(set) var statuses = JourneyState.derive(from: ProjectFacts())
  package private(set) var sources: [ProjectSource] = []
  /// The open Import sheet's model, `nil` when no sheet is shown.
  package private(set) var importing: ImportViewModel?
  package internal(set) var error: UserFacingError?
  /// The last Add's failure, shown on the Import sheet; an error of Run or the Studio is not.
  package private(set) var importError: UserFacingError?
  /// The last scan of the sources in this window: the sheet's plan on Add, or a Rescan the user
  /// asked for; `nil` until then (an M31 scan takes ~90 s, never run on open).
  package internal(set) var scan: ImportPlan? {
    didSet {
      integration = scan.map { IntegrationSummary.make(inventory: $0.inventory) }
      coverage = scan.map(CoverageMatrix.init(plan:))
      series.replace(inventory: scan?.inventory)
    }
  }
  /// The series the next run stacks, from the last scan (card 0095): one run per checked object.
  package let series = StackingStageModel(inventory: nil)
  /// Every stack of the project, oldest first (read on refresh).
  package internal(set) var stacks: [ProjectStack] = []
  /// The runs paused after a lane (card 0097), oldest first: Continue or Discard each.
  package internal(set) var pausedRuns: [ProjectStack] = []
  /// The stack the Studio shows (card 0095), persisted per project; `nil` = the latest.
  package internal(set) var selectedStackID: Int64?
  /// The lights per filter × night of `scan`, computed once per scan.
  package private(set) var integration: IntegrationSummary?
  /// The calibration coverage of `scan`, the matcher's verdict as is.
  package private(set) var coverage: CoverageMatrix?
  /// A Rescan is running.
  package internal(set) var isScanning = false
  var scanTask: Task<Void, Never>?
  /// The scan going is the one Add a night started (card 0100): Run waits for its plan.
  var rescanAfterAdd = false
  /// The preprocessing run the Stacking stage shows: the one running, or the last one.
  package internal(set) var run: RunViewModel?
  /// The scopes still to run after the current one (card 0095: one run per object).
  var queuedScopes: [RunScope] = []
  /// A queue is going: from Run until its last run registered, failed or was cancelled — Run
  /// stays greyed in between two runs too.
  var queueActive = false
  /// The last stack the queue recorded, opened: chosen and loaded in the Studio when the queue
  /// ends (the Studio stage is selected only when it drained).
  var queueRecorded: (stack: ProjectStack, source: LegacyRunSource)?
  /// The stack the Studio shows: the chosen one, else the latest, read-only.
  package internal(set) var studio: LegacyRunModel?
  /// The Studio's working image of the latest stack (card 0087), once its layers are read.
  package internal(set) var workspace: StudioWorkspaceModel?
  /// The Export stage of the Studio's stack (card 0091), once its workspace is open.
  package internal(set) var exportStage: ExportStageModel?
  /// StarNet, the Finder and the clock the Export stage uses.
  @ObservationIgnored let exportServices: ExportServices
  /// The load of `workspace`, owned by the window (not by the pane that shows it).
  @ObservationIgnored var workspaceTask: Task<Void, Never>?
  /// The stack `workspace` (or its load) is of.
  @ObservationIgnored var workspaceStackID: Int64?
  /// The Replay Pipeline chooser is open (card 0088).
  package var isChoosingReplay = false
  /// A pipeline to replay on a stack once its workspace is loaded (card 0088).
  @ObservationIgnored var pendingReplay: PendingReplay?
  /// The Stacking panel's preset and knob edits: what the next run applies (card 0070).
  package let knobs: KnobPanelViewModel
  /// The profile id the knobs' help was last looked up for (`knobs.profile` is its result, nil
  /// when it resolves to nothing); not state a view reads.
  @ObservationIgnored private var profileLookupID: String?
  /// The last run's lanes read-only (this session's result, or the latest stack's `grades.json`),
  /// rebuilt by `refresh()` only when their source changes (card 0069).
  package internal(set) var lastReviewLanes: [FrameReviewViewModel] = []
  /// What `lastReviewLanes` were built from (`run:<id>` or `stack:<id>`), to rebuild once.
  var lastReviewSource: String?
  /// This session's imports, in order: the next run applies all their overrides.
  var imports: [ImportRequest] = []
  @ObservationIgnored private var masterServices: MasterServices?
  /// The first-stack guide's step on screen, `nil` while closed: only `openGuide` opens it.
  package internal(set) var guideStep: Int?
  /// The project is the untitled temporary package: a run needs it saved first (read on refresh).
  package private(set) var needsSave = false
  /// Stack folders no stack records, kept because they hold files (finished masters of a
  /// failed or cancelled run): listed at open and when a queue ends, deleted only by the user.
  package internal(set) var leftoverStacks: [LeftoverStack] = []
  /// The Storage section's stacks with their sizes (card 0114); empty until listed.
  package internal(set) var storage: [StackStorageRow] = []
  /// Bumped by each delete: a size listing that started before one writes nothing.
  @ObservationIgnored var storageDeletes = 0

  let store: () -> ProjectStore?
  let folder: () -> URL?
  let services: (ProjectStore?) -> ImportServices
  let runs: RunServices
  /// The package is saved (not the untitled temporary one a Save moves).
  let isSaved: () -> Bool
  /// Tells the document the project changed, so an untitled one asks to be saved on close.
  let edited: () -> Void
  /// Asks the document to save (the Save panel for an untitled project).
  let saveDocument: () -> Void

  /// A window over the document's current store and package folder (both change when the package
  /// moves); each sheet and run gets fresh `services`, and runs go through `runs`.
  package init(
    store: @escaping () -> ProjectStore?,
    folder: @escaping () -> URL? = { nil },
    services: @escaping (ProjectStore?) -> ImportServices = { ImportPlanning.services(store: $0) },
    runs: RunServices = .live,
    exports: ExportServices = .live,
    isSaved: @escaping () -> Bool = { true },
    edited: @escaping () -> Void = {},
    save: @escaping () -> Void = {}
  ) {
    self.store = store
    self.folder = folder
    self.services = services
    self.runs = runs
    exportServices = exports
    self.isSaved = isSaved
    self.edited = edited
    self.saveDocument = save
    // The panel starts where the latest stack left it; an unreadable record is reported.
    let latest = Result { try store()?.latestStack().map(StackRecord.init(stack:)) }
    let record = (try? latest.get()) ?? nil
    knobs = KnobPanelViewModel(
      mode: record?.mode ?? .deepsky, patch: record?.knobs ?? KnobPatch(),
      ignored: record?.ignoredEntries ?? [])
    // The chosen stack is known before the first refresh, which derives Tri from it (0095): a
    // stack that no longer exists reads as no choice, the latest is shown.
    let settings = Result {
      (
        stage: try store()?.setting(JourneyStage.settingKey),
        stack: try store()?.setting(Self.stackSettingKey).flatMap(Int64.init),
        stacks: try store()?.stacks() ?? []
      )
    }
    if case .success(let saved) = settings {
      stacks = saved.stacks
      selectedStackID = saved.stack.flatMap { id in stacks.contains { $0.id == id } ? id : nil }
      selection = saved.stage.flatMap(JourneyStage.init(rawValue:)) ?? .data
    }
    refresh()
    listLeftoverStacks()
    if case .failure(let failure) = latest { error = UserFacingError(failure) }
    if case .failure(let failure) = settings { error = UserFacingError(failure) }
  }

  /// Shows `id` in the Studio (`nil`: the latest) and remembers it; a stack the project does not
  /// have is not chosen.
  ///
  /// A choice that names the stack already shown is remembered without reopening it (the Studio
  /// only ever shows `selectedStack`).
  package func selectStack(_ id: Int64?) {
    guard id == nil || stacks.contains(where: { $0.id == id }) else { return }
    guard id != selectedStackID || studio == nil else { return }
    // A replay waits for the stack it was chosen for, never for one opened later.
    if pendingReplay?.stackID != id { pendingReplay = nil }
    let shownAlready = studio != nil && (id ?? stacks.last?.id) == selectedStack?.id
    selectedStackID = id
    if !shownAlready {
      studio = nil
      dropWorkspace()
    }
    // Tri follows the stack the Studio shows; the refresh comes first so a failure to persist
    // the choice stays shown.
    refresh()
    do {
      try store()?.setSetting(Self.stackSettingKey, to: id.map(String.init) ?? "")
    } catch {
      self.error = UserFacingError(error)
    }
  }

  /// The stack the Studio shows: the chosen one, else the latest.
  package var selectedStack: ProjectStack? {
    selectedStackID.flatMap { id in stacks.first { $0.id == id } } ?? stacks.last
  }

  /// A stack as the picker lists it: « object · date · n lights » (the project's name for a
  /// stack of every light, no count without a scope).
  package func stackLabel(_ stack: ProjectStack, locale: Locale) -> String {
    let object = studioObject(stack.object)
    let date = Date(timeIntervalSince1970: Double(stack.createdAt) / 1000)
      .formatted(.dateTime.locale(locale).year().month().day().hour().minute())
    let scope = stack.scopeJSON.flatMap {
      try? JSONDecoder().decode(RunScope.self, from: Data($0.utf8))
    }
    let lights = scope.map { AstroFormat(locale: locale).lights($0.lights) }
    return ([object, date] + (lights.map { [$0] } ?? [])).filter { !$0.isEmpty }
      .joined(separator: " · ")
  }

  /// Shows `stage` and remembers it for this project.
  package func select(_ stage: JourneyStage) {
    guard stage != selection else { return }
    selection = stage
    do {
      try store()?.setSetting(JourneyStage.settingKey, to: stage.rawValue)
    } catch {
      self.error = UserFacingError(error)
    }
  }

  /// Saves the project: the Save panel names an untitled one, then Run is offered.
  package func save() {
    saveDocument()
  }

  /// Opens the library master at `path` in the viewer; nothing without master services.
  package func previewMaster(_ path: String) {
    masters?.preview(path)
  }

  /// The master services of this window's planner, built once: the viewer needs no fresh index.
  package var masters: MasterServices? {
    if let masterServices { return masterServices }
    masterServices = services(store()).masters
    return masterServices
  }

  /// A window whose sheets plan with `planning` and have no master services.
  package convenience init(
    store: @escaping () -> ProjectStore?,
    folder: @escaping () -> URL? = { nil },
    planning: @escaping (ProjectStore?) -> ImportViewModel.Planning
  ) {
    self.init(store: store, folder: folder, services: { ImportServices(planning: planning($0)) })
  }

  /// Opens the Import sheet on a fresh request.
  package func startImport() {
    closeImport()
    importError = nil
    let services = services(store())
    let profiles = ImportViewModel.profiles(store: store())
    importing = ImportViewModel(
      planning: services.planning, masters: services.masters, profiles: profiles.profiles,
      rejectedProfiles: profiles.rejected)
  }

  /// Closes the Import sheet and stops its scan, which would otherwise run on for minutes.
  package func closeImport() {
    importing?.cancel()
    importing = nil
  }

  /// Records the imported folders as read-only sources of the project and closes the sheet; the
  /// next run applies the request's overrides.
  ///
  /// Recording is idempotent per folder: after a failure part-way, Add again records the rest.
  /// A night added through the sheet to a project that has some is followed by a rescan of them
  /// all (card 0100); any other plan the window cannot adopt waits for the user's Rescan.
  package func add(_ request: ImportRequest) {
    guard let store = store() else {
      error = .projectClosed
      importError = error
      return
    }
    let isNewNight = addsANight(request)
    var recorded = 0
    do {
      for path in request.paths {
        try store.addSource(kind: .night, path: path)
        recorded += 1
      }
      // The profile kept for these sources, recorded with them; applied by nothing here.
      if let importing, let kept = importing.profileToRecord(for: request) {
        for path in request.paths {
          try store.setProfile(kept.id, kind: .night, path: path)
        }
      }
      imports.append(request)
      edited()
      // The sources first: whether the sheet's plan is the project's scan depends on them.
      refresh()
      adoptScan(of: importing, for: request)
      closeImport()
      refresh()
      if isNewNight && scan == nil {
        rescan()
        rescanAfterAdd = isScanning
      }
    } catch {
      // Some folders may be recorded: the last scan no longer describes the project.
      if recorded > 0 { edited() }
      dropScan()
      refresh()
      self.error = UserFacingError(error)
      importError = self.error
    }
  }

  /// Rereads the sources and the stage states; never changes the selection.
  package func refresh() {
    do {
      let store = store()
      needsSave = !isSaved()
      sources = try store?.sources() ?? []
      // The profile kept at import (0060) words the knobs' help; it is applied by nothing here.
      // Every night must have kept the same profile (a night without one counts, a legacy run
      // does not): no guessing. Looked up once per agreed id (nothing saves a user copy from the
      // app yet; the card that does invalidates this).
      let agreed = Self.agreedProfileID(sources)
      if agreed != profileLookupID {
        profileLookupID = agreed
        knobs.profile = agreed.flatMap { id in
          ImportViewModel.profiles(store: store).profiles.first { $0.id == id }
        }
      }
      let summary = try store?.summary() ?? ProjectSummary()
      // The stacks are read again only when their count moved: a refresh runs on every event.
      // A queue's stacks appear when it ends: until then the picker, Tri and « the latest » stay.
      if !queueActive, summary.stacks != stacks.count { stacks = try store?.stacks() ?? [] }
      // Paused runs change only between runs (a pause recorded, a Continue, a Discard), and the
      // list is hidden while one goes: no read per run event.
      if !isStacking {
        let paused = try store?.pausedStacks() ?? []
        if paused != pausedRuns { pausedRuns = paused }
      }
      let running = isStacking ? 1 : 0
      var facts = ProjectFacts(summary: summary, coverage: coverage, stacksRunning: running)
      // Tri is done when the stack the Studio shows (the chosen one, else the latest; 0095) went
      // through the review (card 0069). A record that no longer decodes was reported where it is
      // read (init, Run); here it only means « not reviewed », never a window whose stages stop
      // refreshing.
      let shown = selectedStack
      facts.framesReviewed =
        (shown.flatMap { try? StackRecord(stack: $0) })?.framesReviewed ?? false
      statuses = JourneyState.derive(from: facts)
      refreshReviewLanes(latest: shown)
      error = nil
    } catch {
      self.error = UserFacingError(error)
    }
  }

  /// The profile every capture night of `sources` kept at import, or `nil` when they differ or
  /// one kept none (a legacy run has no say): the knobs' help and the Studio's step 0 read it.
  nonisolated static func agreedProfileID(_ sources: [ProjectSource]) -> String? {
    let kept = Set(sources.filter { $0.kind == .night }.map(\.profileID))
    return kept.count == 1 ? kept.first.flatMap { $0 } : nil
  }
}
