import Foundation
import ImageKit
import Metal
import ProcessKit
import Testing

@Suite(
  "GPUImage and ProcessLibrary: upload, read back, refuse what cannot run",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct GPUImageTests {
  @Test("an AstroImage round-trips through the GPU bit-exactly; a short plane is refused")
  func testUploadReadBack() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let header = try FITSFile.parse(Data(("END" + String(repeating: " ", count: 2877)).utf8)).header
    let planes: [[Float]] = [[0.5, -0.25, .infinity, 1e-30], [1, 2, 3, 4]]
    let image = AstroImage(
      width: 2, height: 2, planes: planes, metadata: ImageMetadata(header: header))
    let gpu = try GPUImage(device: device, image: image)
    #expect(gpu.read().map { $0.map(\.bitPattern) } == planes.map { $0.map(\.bitPattern) })
    #expect(throws: ProcessError.sizeMismatch) {
      try GPUImage(device: device, width: 2, height: 2, planes: [[1, 2, 3]])
    }
  }

  @Test(
    "a kernel that does not compile, or a missing function, is a shader error",
    arguments: [("kernel void broken( {", "broken"), (GainKernel.source, "absent")])
  func testShaderErrors(source: String, function: String) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    #expect {
      try ProcessLibrary.pipeline(device: device, source: source, function: function)
    } throws: { error in
      guard case ProcessError.shader(let message) = error else { return false }
      return message.hasPrefix(function)
    }
  }
}
