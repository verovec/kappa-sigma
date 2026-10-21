package import Foundation
internal import ProjectKit

/// A new project named after its target (« M 31 »), in the projects folder (design §4.5).
package enum NewProject {
  /// Where projects are created: `~/AstroStack/Projects`.
  package static var projectsFolder: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("AstroStack/Projects", isDirectory: true)
  }

  /// Creates `<target>.astrostack` in `folder` and returns it; a target already there gets the
  /// next free « M 31 2 », so an existing project is never overwritten.
  package static func create(target: String, in folder: URL = projectsFolder) throws -> URL {
    let name = fileName(target)
    guard !name.isEmpty else { throw UserFacingError.projectName }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = freeURL(for: name, in: folder)
    try ProjectPackage.create(at: url).close()
    return url
  }

  /// `target` as a file name: one line, no typed `.astrostack`, path separators turned into
  /// dashes, no leading dot (a hidden package would vanish from the Finder).
  static func fileName(_ target: String) -> String {
    var name = target.components(separatedBy: .controlCharacters).joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
    let suffix = ".\(ProjectPackage.fileExtension)"
    if name.lowercased().hasSuffix(suffix) { name.removeLast(suffix.count) }
    let cleaned = name.replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let visible = cleaned.drop { $0 == "." || $0 == "-" }
    return String(visible).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func freeURL(for name: String, in folder: URL) -> URL {
    func url(_ suffix: Int) -> URL {
      folder.appendingPathComponent(suffix == 1 ? name : "\(name) \(suffix)")
        .appendingPathExtension(ProjectPackage.fileExtension)
    }
    var suffix = 1
    while FileManager.default.fileExists(atPath: url(suffix).path) { suffix += 1 }
    return url(suffix)
  }
}
