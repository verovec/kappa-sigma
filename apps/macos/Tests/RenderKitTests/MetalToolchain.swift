import Foundation
import Metal
import RenderKit

/// The offline Metal compiler (`xcrun metal`), present with Xcode + the Metal Toolchain only.
enum MetalToolchain {
  static let available: Bool = (try? run(["xcrun", "-sdk", "macosx", "metal", "--version"])) == 0

  /// Compiles the bundled shader sources with `xcrun metal` into a .metallib and loads it.
  static func compileLibrary(device: MTLDevice) throws -> MTLLibrary {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("metal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let sources = try ShaderLibrary.sourceFolder()
    let output = folder.appendingPathComponent("RenderKit.metallib").path
    let files = ShaderLibrary.sourceFiles.map { sources.appendingPathComponent($0).path }
    let status = try run(
      ["xcrun", "-sdk", "macosx", "metal", "-fno-fast-math", "-I", sources.path, "-o", output]
        + files)
    guard status == 0 else { throw GPUTestError.noTexture }
    return try device.makeLibrary(URL: URL(fileURLWithPath: output))
  }

  @discardableResult
  private static func run(_ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }
}
