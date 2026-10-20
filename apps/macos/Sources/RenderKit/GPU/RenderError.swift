/// Why the GPU side could not do its job.
package enum RenderError: Error, Equatable, Sendable {
  /// No Metal device on this Mac.
  case noDevice
  /// A texture could not be allocated (too large for the device, or out of memory).
  case textureAllocationFailed(width: Int, height: Int)
  /// The shader sources are missing from RenderKit's resources: a broken build.
  case shaderSourcesMissing(path: String)
  /// A kernel is absent from the library.
  case missingFunction(String)
  /// A command buffer or encoder could not be created, or the GPU reported an error.
  case commandFailed(String)
}
