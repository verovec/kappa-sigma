package import Foundation
internal import Observation
package import StackKit

/// The state of the Import sheet: the request the controls edit and the plan StackKit returns.
///
/// Every control writes one `ImportRequest` field and rescans; the model never classifies or
/// matches anything itself (R2: the verdicts shown are StackKit's, and the overrides win).
@Observable
package final class ImportViewModel {
  /// Scans a request and plans it, off the main actor.
  package typealias Planning = @Sendable (ImportRequest) async throws -> ImportPlan
  /// `Planning` that reports where the scan is to its second argument.
  package typealias ProgressPlanning =
    @Sendable (ImportRequest, @escaping @Sendable (ScanProgress) -> Void) async throws
    -> ImportPlan

  /// The channels a light filter can be mapped to: the canonical filters, or dropped.
  package static let channels = Filter.allCases.map(\.rawValue) + [ignored]
  /// The channel that drops a filter from the stack.
  package static let ignored = "ignore"

  package private(set) var request = ImportRequest(paths: [])
  package private(set) var plan: ImportPlan?
  package private(set) var isScanning = false
  /// Where the running scan is; `nil` when none runs (or a calibration-only replan does).
  package private(set) var progress: ScanProgress?
  package private(set) var error: UserFacingError?
  /// The sets the user excluded, as they were listed when excluded (a scan drops them).
  package private(set) var excludedRows: [ImportPlan.SetRow] = []

  /// What a master's disclosure can do (inspect, rebuild, preview); `nil` hides it.
  package let masters: MasterServices?

  private let planning: ProgressPlanning
  private var scan: Task<Void, Never>?
  /// The request the shown plan's scan was made for.
  private var scanned: ImportRequest?

  /// A model planning through `planning`, which reports its progress, with the master `masters`
  /// services if any.
  package init(planning: @escaping ProgressPlanning, masters: MasterServices? = nil) {
    self.planning = planning
    self.masters = masters
  }

  /// A model planning through `planning`, which reports no progress.
  package convenience init(planning: @escaping Planning, masters: MasterServices? = nil) {
    self.init(planning: { request, _ in try await planning(request) }, masters: masters)
  }

  /// The light filters as captured, in canonical order: the rows of the filter map.
  ///
  /// The scan names lights after the map, so a mapping target stands for its source.
  package var lightFilters: [String] {
    let targets = Set(request.filterMap.values)
    let lights = plan?.inventory.sets.filter { $0.key.type == .light }.map(\.key.filter) ?? []
    return Set(lights.filter { !targets.contains($0) } + request.filterMap.keys)
      .sorted(by: Filter.less)
  }

  /// Whether `row` can be excluded: the scan excludes by the ids of an unmapped scan, so a set
  /// whose filter may come from the filter map has no id to exclude it by.
  package func canExclude(_ row: ImportPlan.SetRow) -> Bool {
    !request.filterMap.values.contains(row.filter)
  }

  // MARK: - Controls

  /// Starts over on `folder`: no override survives a change of capture.
  package func choose(folder: URL) {
    request = ImportRequest(paths: [folder.path])
    excludedRows = []
    refresh()
  }

  /// Asserts the clip filter of a colour light set; `unknown` hands it back to the pixels.
  package func setFilterSet(_ value: FilterSet, for row: ImportPlan.SetRow) {
    request.filterSets[row.id] = value.isKnown ? value : nil
    refresh()
  }

  /// Maps a light filter to a channel (`ignore` drops it); `nil` removes the mapping.
  package func mapFilter(_ filter: String, to channel: String?) {
    request.filterMap[filter] = channel
    refresh()
  }

  /// Mono, colour, or the scan's verdict.
  package func setColorModel(_ choice: ColorChoice) {
    request.colorModel = choice
    refresh()
  }

  /// Applies the masters even where they do not match.
  package func setForceCalibration(_ force: Bool) {
    request.forceCalibration = force
    refresh()
  }

  /// Checks or unchecks one proposed master.
  package func setIncluded(_ included: Bool, _ cell: ImportPlan.Cell) {
    request.calibExclude.removeAll { $0 == cell.suggestionID }
    if !included { request.calibExclude.append(cell.suggestionID) }
    refresh()
  }

  /// Drops a whole set from the scan.
  package func exclude(_ row: ImportPlan.SetRow) {
    guard canExclude(row), !request.excludeSets.contains(row.id) else { return }
    request.excludeSets.append(row.id)
    excludedRows.append(row)
    refresh()
  }

  /// Puts an excluded set back.
  package func restore(_ row: ImportPlan.SetRow) {
    request.excludeSets.removeAll { $0 == row.id }
    excludedRows.removeAll { $0.id == row.id }
    refresh()
  }

  // MARK: - Scanning

  /// Scans the current request again (the folder may have changed on disk).
  package func rescan() {
    refresh(force: true)
  }

  /// Plans the current request, cancelling a scan still running for an older one; a change of
  /// calibration choices only rematches the last scan.
  private func refresh(force: Bool = false) {
    scan?.cancel()
    guard !request.paths.isEmpty else { return }
    let request = request
    let rescans = force || (scanned.map { ImportPlanner.needsScan(from: $0, to: request) } ?? true)
    let last = rescans ? nil : plan
    isScanning = true
    progress = nil
    scan = Task {
      do {
        let plan =
          if let last {
            await ImportPlanner.replanned(last, request: request)
          } else {
            try await scanReporting(request)
          }
        guard !Task.isCancelled else { return }
        self.plan = plan
        scanned = request
        error = nil
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        plan = nil
        scanned = nil
        self.error = UserFacingError(error)
      }
      isScanning = false
      progress = nil
    }
  }

  /// `planning(request)`, called from the scan task itself (scans start in the order the controls
  /// asked), its progress consumed by a child task into `progress` (newest value only: the sheet
  /// shows where the scan is, not every step it took).
  private func scanReporting(_ request: ImportRequest) async throws -> ImportPlan {
    let (steps, continuation) = AsyncStream.makeStream(
      of: ScanProgress.self, bufferingPolicy: .bufferingNewest(1))
    async let watched: Void = watch(steps)
    defer { continuation.finish() }
    let plan = try await planning(request) { continuation.yield($0) }
    continuation.finish()
    await watched
    return plan
  }

  /// Shows each step of `steps` until the stream ends or the scan is cancelled.
  private func watch(_ steps: AsyncStream<ScanProgress>) async {
    for await step in steps where !Task.isCancelled { progress = step }
  }

  /// Stops the scan in flight: the sheet is closing and nothing will read its plan.
  package func cancel() {
    scan?.cancel()
    isScanning = false
    progress = nil
  }

  /// Stops the scan in flight and goes back to what the sheet showed before it: the last plan
  /// and its request, or nothing.
  package func cancelScan() {
    cancel()
    request = scanned ?? ImportRequest(paths: [])
    if scanned == nil { plan = nil }
  }

  /// Waits for the scan in flight, if any.
  package func settled() async {
    await scan?.value
  }
}
