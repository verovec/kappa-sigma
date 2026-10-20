package import Metal
internal import RenderKit

/// Builds a process's compute pipelines with RenderKit's compile options (Metal 3.1, fast-math
/// off): every process kernel is oracle-pinned.
package enum ProcessLibrary {
  /// The pipeline of `function` in the Metal `source`.
  package static func pipeline(
    device: MTLDevice, source: String, function: String
  ) throws -> MTLComputePipelineState {
    let library: MTLLibrary
    do {
      library = try device.makeLibrary(source: source, options: ShaderLibrary.compileOptions)
    } catch {
      throw ProcessError.shader("\(function): \(error)")
    }
    guard let kernel = library.makeFunction(name: function) else {
      throw ProcessError.shader("\(function): missing")
    }
    return try device.makeComputePipelineState(function: kernel)
  }
}
