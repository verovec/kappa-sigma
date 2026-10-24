import ProcessKit
import Testing

/// What the registry declares about its processes as a whole (card 0118: which run on a branch).
@Suite("ProcessRegistry — the branchable audit")
struct ProcessRegistryTests {
  /// Every process a branch takes, and on which layers: per-image, linear, same canvas.
  static let branchable: [String: BranchUse] = [
    DenoiseProcess.id: .anyLayer,
    ColourBalanceProcess.id: .colourLayers,
    ColourCalibrationProcess.id: .colourLayers,
  ]

  @Test("testBranchableAudit")
  func testBranchableAudit() throws {
    let registry = try ProcessRegistry.standard()
    let declared = registry.types.filter { $0.branchable != .never }
    #expect(
      Dictionary(uniqueKeysWithValues: declared.map { ($0.id, $0.branchable) }) == Self.branchable)
    for type in declared {
      #expect(type.stage == .linear, "\(type.id) is linear")
      #expect(!(type is any GeometricProcess.Type), "\(type.id) keeps the canvas")
      #expect(type.outputChannels(input: 1) == 1, "\(type.id) keeps the planes")
      #expect(type.outputChannels(input: 3) == 3, "\(type.id) keeps the planes")
    }
  }
}
