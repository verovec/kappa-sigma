import Foundation
import StringCatalog
import Testing

/// RenderKit's shared components (card 0075) speak only through its catalog: every component every
/// later panel reuses is in French and English from the start. The tokens hold SF Symbol names and
/// the debug gallery sample tool names, units and paths — code, not words — so only `Components/`
/// is gated.
@Suite("Design system — no English literal outside RenderKit's catalog")
struct DesignSystemCatalogTests {
  @Test("every shared component resolves its words from the catalog")
  func testDesignSystemLiteralsAreCatalogued() throws {
    let catalog = try Catalogs.shipped("RenderKit")
    let folder = try Catalogs.folder("RenderKit").appendingPathComponent("DesignSystem/Components")
    let files =
      (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
      .allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    #expect(files.count >= 8, "the design system's sources were found")
    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      let name = file.deletingPathExtension().lastPathComponent
      #expect(CatalogAudit.uncatalogued(in: source, file: name, catalog: catalog) == [], "\(name)")
    }
  }
}
