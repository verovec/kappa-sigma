import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

@MainActor
@Suite("NewProject: a project named after its target, never overwriting one")
struct NewProjectTests {
  @Test(
    "the package is named after the target, cleaned for the file system",
    .scratchDirectory,
    arguments: zip(
      ["M 31", "  NGC 7000 ", "IC 1848/Soul", "Sh2:155", ".hidden"],
      ["M 31", "NGC 7000", "IC 1848-Soul", "Sh2-155", "hidden"]))
  func testCreatesTargetPackage(_ target: String, _ expected: String) throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("Projects")

    let url = try NewProject.create(target: target, in: folder)

    #expect(url.lastPathComponent == "\(expected).\(ProjectPackage.fileExtension)")
    let package = try ProjectPackage.open(at: url)
    try package.close()
  }

  @Test(
    "a second project of the same target is suffixed; the first is left as it was",
    .scratchDirectory)
  func testCollisionIsSuffixed() throws {
    let folder = try ScratchDirectory.url
    let first = try NewProject.create(target: "M 31", in: folder)
    let marker = first.appendingPathComponent("marker")
    try Data("kept".utf8).write(to: marker)

    let second = try NewProject.create(target: "M 31", in: folder)
    let third = try NewProject.create(target: "M 31", in: folder)

    #expect(second.lastPathComponent == "M 31 2.astrostack")
    #expect(third.lastPathComponent == "M 31 3.astrostack")
    #expect(try Data(contentsOf: marker) == Data("kept".utf8))
  }

  @Test(
    "a name with nothing left once cleaned is refused", .scratchDirectory,
    arguments: ["", "   ", "...", "/"])
  func testEmptyNameIsRefused(_ target: String) throws {
    let folder = try ScratchDirectory.url

    #expect(throws: UserFacingError.projectName) {
      try NewProject.create(target: target, in: folder)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
  }

  @Test("the refusal says what to type, in English and in French")
  func testEmptyNameMessage() {
    #expect(UserFacingError.projectName.message.text("en").contains("target"))
    #expect(UserFacingError.projectName.message.text("fr").contains("cible"))
  }

  @Test("projects live in ~/AstroStack/Projects (design §4.5)")
  func testProjectsFolder() {
    #expect(NewProject.projectsFolder.path.hasSuffix("/AstroStack/Projects"))
  }
}
