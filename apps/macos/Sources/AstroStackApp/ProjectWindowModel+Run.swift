internal import Foundation
internal import ProjectKit
package import StackKit

/// The Stacking stage's run and the Studio's stack.
extension ProjectWindowModel {
  /// The import the next run plans: every capture night of the project, with the overrides of
  /// the last import this session, else those stored with the latest stack; `nil` without a night.
  var runRequest: ImportRequest? {
    let nights = sources.filter { $0.kind == .night }.map(\.path)
    guard !nights.isEmpty else { return nil }
    var request = lastImport ?? latestStackRequest ?? ImportRequest(paths: nights)
    request.paths = nights
    return request
  }

  /// The target, as the project is named (`M31.astrostack` → `M31`).
  var targetName: String { folder()?.deletingPathExtension().lastPathComponent ?? "" }

  /// Runs preprocessing on the project's nights into `stacks/<run_id>/` of the package.
  ///
  /// The import is planned again (scan + calibration plan, the overrides as left), then StackKit
  /// runs it. A finished run becomes a stack with one image per bundle layer and the Studio opens
  /// it; a cancelled or failed one registers nothing and keeps its artifacts. One run at a time.
  package func startRun(mode: PreprocessRequest.Mode = .deepsky) {
    guard run?.isRunning != true, let request = runRequest else { return }
    guard let store = store(), let folder = folder() else {
      error = .projectClosed
      return
    }
    let runID = runs.nextRunID
    let output = folder.appendingPathComponent("stacks/\(runID)", isDirectory: true)
    let work = runs.scratch.appendingPathComponent("run_\(runID)", isDirectory: true)
    let planning = services(store).planning
    let start = runs.run
    let model = RunViewModel(runID: runID, output: output)
    run = model
    refresh()
    model.start(
      {
        let plan = try await planning(request)
        return start(
          PreprocessRequest(
            inventory: plan.inventory, output: output, work: work, runID: runID, mode: mode,
            library: plan.library))
      },
      completion: { [weak self] outcome in
        // Siril's work files are tens of GB per night and never reused (job-scratch lesson).
        try? FileManager.default.removeItem(at: work)
        guard let self else { return }
        if case .success(let result) = outcome {
          register(result, request: request, runID: runID, output: output)
        } else {
          refresh()
        }
      })
  }

  /// Cancels the running run; its finished masters stay in its folder.
  package func cancelRun() {
    run?.cancel()
  }

  /// Opens the latest stack in the Studio, off the main actor (bundle and FITS headers).
  package func openStudio() async {
    guard studio == nil, let folder = folder() else { return }
    do {
      guard let stack = try store()?.stacks().last else { return }
      let source = try await Self.openStack(
        folder.appendingPathComponent(stack.bundlePath), object: targetName)
      studio = studio ?? LegacyRunModel(source: source)
    } catch {
      self.error = UserFacingError(error)
    }
  }

  @concurrent
  private nonisolated static func openStack(_ folder: URL, object: String) async throws
    -> LegacyRunSource
  {
    try LegacyRunSource(stack: folder, object: object)
  }

  /// Records a finished run as a stack of the nights it read, with its request as parameters,
  /// and shows it in the Studio.
  private func register(
    _ result: PreprocessResult, request: ImportRequest, runID: String, output: URL
  ) {
    do {
      guard let store = store() else { throw UserFacingError.projectClosed }
      let bundle = try result.bundle ?? BundleWriter.read(from: output)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let params = String(bytes: try encoder.encode(request), encoding: .utf8) ?? "{}"
      let read = sources.filter { request.paths.contains($0.path) }.map(\.id)
      let stack = try store.addStack(
        bundlePath: "stacks/\(runID)", sourceIDs: read, paramsJSON: params)
      for layer in bundle.layers {
        try store.addImage(stackID: stack.id, role: layer.id)
      }
      studio = LegacyRunModel(source: try LegacyRunSource(stack: output, object: targetName))
      refresh()
      select(.studio)
    } catch {
      refresh()
      self.error = UserFacingError(error)
    }
  }

  /// The request stored with the latest stack (this app wrote it); `nil` without one.
  private var latestStackRequest: ImportRequest? {
    guard let stack = try? store()?.stacks().last else { return nil }
    return try? JSONDecoder().decode(ImportRequest.self, from: Data(stack.paramsJSON.utf8))
  }
}
