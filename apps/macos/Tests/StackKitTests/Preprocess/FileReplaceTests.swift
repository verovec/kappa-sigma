import Foundation
import StackKit
import TestSupport
import Testing

/// `FileReplace.detach`: a write to the pipeline's copy of a frame never reaches the capture it
/// was linked from (R7: captures are read-only).
@Suite("FileReplace — links detached before any in-place write")
struct FileReplaceTests {
  @Test("a link becomes a private copy; the capture keeps its bytes", .scratchDirectory)
  func testDetachLeavesTheTargetAlone() throws {
    let folder = try ScratchDirectory.url
    let capture = folder.appendingPathComponent("capture.fits")
    let link = folder.appendingPathComponent("light_00001.fits")
    try Data("capture".utf8).write(to: capture)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: capture)

    try FileReplace.detach(link)
    try Data("edited".utf8).write(to: link)

    let type =
      try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
    #expect(type == .typeRegular)
    #expect(try Data(contentsOf: capture) == Data("capture".utf8))
    #expect(try Data(contentsOf: link) == Data("edited".utf8))
  }

  @Test("a plain file is left as it is", .scratchDirectory)
  func testDetachKeepsAPlainFile() throws {
    let file = try ScratchDirectory.url.appendingPathComponent("pp_light_00001.fits")
    try Data("calibrated".utf8).write(to: file)
    try FileReplace.detach(file)
    #expect(try Data(contentsOf: file) == Data("calibrated".utf8))
  }
}
