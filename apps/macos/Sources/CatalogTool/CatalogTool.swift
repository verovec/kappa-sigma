internal import Foundation
internal import StringCatalog

/// Build tool run by `CatalogPlugin`: `CatalogTool <catalog.xcstrings> <output folder>`.
///
/// Compiles the catalog into `<language>.lproj` tables (`CatalogCompiler`); a catalog that
/// fails the gate fails the build with the reasons, so a missing French value never ships.
@main
enum CatalogTool {
  static func main() {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else {
      FileHandle.standardError.write(Data("usage: CatalogTool <catalog> <folder>\n".utf8))
      exit(64)
    }
    do {
      let catalog = try StringCatalog(contentsOf: URL(fileURLWithPath: arguments[1]))
      try CatalogCompiler.compile(catalog, into: URL(fileURLWithPath: arguments[2]))
    } catch {
      FileHandle.standardError.write(Data("error: \(arguments[1]): \(error)\n".utf8))
      exit(1)
    }
  }
}
