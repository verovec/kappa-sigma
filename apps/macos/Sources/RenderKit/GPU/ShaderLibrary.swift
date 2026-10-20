package import Foundation
package import Metal

/// RenderKit's Metal library.
///
/// A precompiled `RenderKit.metallib` from the resources when one is there (Xcode builds, E19),
/// else the same `.metal` sources compiled at runtime — the only path with the Command Line
/// Tools. Both use the same sources and fast-math off (oracle-pinned
/// kernels must match their CPU references).
package enum ShaderLibrary {
  /// The shader sources, in compile order (each includes `ShaderTypes.h`).
  package static let sourceFiles = ["Display.metal", "Histogram.metal"]
  /// Every kernel the library must expose.
  package static let kernelNames: Set<String> = ["display", "histogram", "shaderLayout"]

  /// The precompiled library if bundled, else the runtime-compiled one.
  package static func load(device: MTLDevice) throws -> MTLLibrary {
    if let precompiled = try? sourceFolder().appendingPathComponent("RenderKit.metallib"),
      FileManager.default.fileExists(atPath: precompiled.path)
    {
      return try device.makeLibrary(URL: precompiled)
    }
    return try compileSources(device: device)
  }

  /// Compiles the bundled sources with `makeLibrary(source:)`; `#include "ShaderTypes.h"` is
  /// inlined because the runtime compiler has no include path.
  package static func compileSources(device: MTLDevice) throws -> MTLLibrary {
    let folder = try sourceFolder()
    let header = try String(
      contentsOf: folder.appendingPathComponent("ShaderTypes.h"), encoding: .utf8)
    let source = try sourceFiles.map { name in
      try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        .replacingOccurrences(of: "#include \"ShaderTypes.h\"", with: "")
    }
    return try device.makeLibrary(
      source: header + "\n" + source.joined(separator: "\n"), options: compileOptions)
  }

  /// Metal 3, IEEE-correct math: fast-math off for oracle-pinned kernels.
  package static var compileOptions: MTLCompileOptions {
    let options = MTLCompileOptions()
    options.languageVersion = .version3_1
    options.mathMode = .safe
    options.mathFloatingPointFunctions = .precise
    return options
  }

  /// The folder holding the `.metal` sources and `ShaderTypes.h`.
  package static func sourceFolder() throws -> URL {
    let bundle = RenderKitResources.bundle
    guard let folder = bundle.url(forResource: "Shaders", withExtension: nil) else {
      throw RenderError.shaderSourcesMissing(path: bundle.bundleURL.path)
    }
    return folder
  }
}
