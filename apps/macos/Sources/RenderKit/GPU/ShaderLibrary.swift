package import Foundation
package import Metal

/// RenderKit's Metal library.
///
/// A precompiled `RenderKit.metallib` from the resources when one is there (Xcode builds, E19),
/// else the same `.metal` sources compiled at runtime — the only path with the Command Line
/// Tools. Both use the same sources and fast-math off (oracle-pinned
/// kernels must match their CPU references).
package enum ShaderLibrary {
  /// The shader sources, in compile order (each includes the `headerFiles` it needs).
  package static let sourceFiles = ["Display.metal", "Histogram.metal"]
  /// The headers the sources include: the uniform structs and the shared STF functions.
  package static let headerFiles = ["ShaderTypes.h", "STF.h"]
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

  /// Compiles the bundled sources with `makeLibrary(source:)`; the `headerFiles` are inlined
  /// once ahead of the sources because the runtime compiler has no include path.
  package static func compileSources(device: MTLDevice) throws -> MTLLibrary {
    let folder = try sourceFolder()
    let headers = try headerFiles.map { name in
      try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }
    let source = try sourceFiles.map { name in
      var text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
      for header in headerFiles {
        text = text.replacingOccurrences(of: "#include \"\(header)\"", with: "")
      }
      return text
    }
    return try device.makeLibrary(
      source: (headers + source).joined(separator: "\n"), options: compileOptions)
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
