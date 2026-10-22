internal import Foundation
package import Metal
internal import RenderKit

/// Builds a process's compute pipelines with RenderKit's compile options (Metal 3.1, fast-math
/// off): every process kernel is oracle-pinned.
package enum ProcessLibrary {
  /// RenderKit's header of the screen transfer function, shared with the process kernels.
  package static let sharedHeader = "STF.h"

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
    try pipeline(library: library(device: device, file: file), function: function)
  }

  /// ProcessKit's bundled `Shaders/<file>`, compiled once for several pipelines.
  ///
  /// `#include "STF.h"` is replaced by RenderKit's header (the runtime compiler has no include
  /// path): the display, the stretch and the levels share one MTF.
  package static func library(device: MTLDevice, file: String) throws -> MTLLibrary {
    let bundle = ProcessKitResources.bundle
    guard let url = bundle.url(forResource: "Shaders/" + file, withExtension: nil),
      var source = try? String(contentsOf: url, encoding: .utf8)
    else { throw ProcessError.shader("\(file) missing from ProcessKit's resources") }
    let include = "#include \"\(sharedHeader)\""
    if source.contains(include) {
      guard
        let header = try? String(
          contentsOf: ShaderLibrary.sourceFolder().appendingPathComponent(sharedHeader),
          encoding: .utf8)
      else { throw ProcessError.shader("\(sharedHeader) missing from RenderKit's resources") }
      source = source.replacingOccurrences(of: include, with: header)
    }
    do {
      return try device.makeLibrary(source: source, options: ShaderLibrary.compileOptions)
    } catch {
      throw ProcessError.shader("\(file): \(error)")
    }
  }

  /// The pipeline of `function` in a compiled `library`.
  package static func pipeline(
    library: MTLLibrary, function: String
  ) throws -> MTLComputePipelineState {
    guard let kernel = library.makeFunction(name: function) else {
      throw ProcessError.shader("\(function): missing")
    }
    return try library.device.makeComputePipelineState(function: kernel)
  }
}
