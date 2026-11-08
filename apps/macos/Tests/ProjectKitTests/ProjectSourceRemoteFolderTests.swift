import ProjectKit
import Testing

@Suite("ProjectSource — the bucket and prefix a remote night reads")
struct ProjectSourceRemoteFolderTests {
  struct PathRow: Sendable, CustomTestStringConvertible {
    let path: String
    let bucket: String?
    let prefix: String?
    var testDescription: String { path }
  }

  @Test(
    "a virtual path names its bucket and prefix, the bucket's root as empty; a file names none",
    arguments: [
      PathRow(path: "s3://astro/M31/n1", bucket: "astro", prefix: "M31/n1"),
      PathRow(path: "s3://astro", bucket: "astro", prefix: ""),
      PathRow(path: "s3://astro/", bucket: "astro", prefix: ""),
      PathRow(path: "s3:///M31", bucket: nil, prefix: nil),
      PathRow(path: "/Volumes/astro/M31", bucket: nil, prefix: nil),
    ])
  func testRemoteFolder_ofPath(row: PathRow) {
    let folder = ProjectSource.remoteFolder(of: row.path)

    #expect(folder?.bucket == row.bucket && folder?.prefix == row.prefix)
  }

  @Test("a frame's key is the path's prefix, never the bucket's root")
  func testRemoteParts_needsAKey() {
    #expect(ProjectSource.remoteParts(of: "s3://astro/M31/l.fits")?.key == "M31/l.fits")
    #expect(ProjectSource.remoteParts(of: "s3://astro/") == nil)
    #expect(ProjectSource.remoteParts(of: "s3://astro") == nil)
  }
}
