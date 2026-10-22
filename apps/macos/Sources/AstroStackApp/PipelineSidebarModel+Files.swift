package import ProcessKit

extension PipelineSidebarModel {
  /// The pipelines saved in the project, by name.
  package var savedNames: [String] {
    (try? store.pipelineNames()) ?? []
  }

  /// Saves the pipeline shown under `name` in the project (replacing one of that name).
  package func save(as name: String) {
    do {
      var named = pipeline
      named.name = name
      try store.savePipeline(named: name, json: named.json())
      rename(name)
    } catch {
      failure = UserFacingError(error).message
    }
  }

  /// Shows the saved pipeline `name`, with what its loading ignored or changed.
  package func load(_ name: String) {
    do {
      let loaded = try saved(name)
      show(loaded.pipeline, warnings: loaded.warnings)
    } catch {
      failure = UserFacingError(error).message
    }
  }

  /// The differences from the saved pipeline `name` to the one shown (the compare sheet).
  package func differences(from name: String) throws -> [PipelineDiff.Entry] {
    PipelineDiff.entries(try saved(name).pipeline, pipeline)
  }

  private func saved(_ name: String) throws -> Pipeline.Loaded {
    guard let data = try store.pipeline(named: name) else {
      throw PipelineFileError.malformed("no pipeline named \(name)")
    }
    return try Pipeline.load(data, registry: workspace.registry)
  }
}
