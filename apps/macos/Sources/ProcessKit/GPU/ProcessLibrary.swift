internal import Foundation
internal import ImageKit
package import Metal
internal import RenderKit

/// Builds a process's compute pipelines with RenderKit's compile options (Metal 3.1, fast-math
/// off): every process kernel is oracle-pinned.
package enum ProcessLibrary {
  /// SwiftPM's resource bundle for ProcessKit.
  private static let bundleName = "AstroStack_ProcessKit.bundle"

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

  /// The pipeline of `function` in ProcessKit's bundled `Shaders/<file>`.
  package static func pipeline(
    device: MTLDevice, file: String, function: String
  ) throws -> MTLComputePipelineState {
    let bundle = KitBundle.resolve(named: bundleName) { Bundle.module }
    guard let url = bundle.url(forResource: "Shaders/" + file, withExtension: nil),
      let source = try? String(contentsOf: url, encoding: .utf8)
    else { throw ProcessError.shader("\(function): \(file) missing from ProcessKit's resources") }
    return try pipeline(device: device, source: source, function: function)
  }
}
