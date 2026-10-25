package import Foundation

/// Siril's five lists read from disk (legacy `records.go`): header-driven, so the 6-column Messier,
/// NGC and IC files, the 4-column Sh2 and the 3-column LDN share one parser.
extension SkyCatalogue {
  /// The catalogue of the Siril that `environment` names (`SIRIL_BIN`, else the app): its lists
  /// merged, the OpenNGC overlay on top.
  package static func installed(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> Self {
    let siril = SirilTool.path(environment: environment)
    do {
      try SirilTool.requireExecutable(siril)
    } catch {
      throw SkyCatalogueError.sirilMissing(path: siril)
    }
    let folder = installedFolder(environment: environment)
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder),
      isFolder.boolValue
    else { throw SkyCatalogueError.catalogueMissing(folder: folder.path) }
    let catalogue = try load(folder: folder, overlay: nil)
    // Lists that yield no object are no catalogue, never an empty one shown as such.
    guard !catalogue.objects.isEmpty else { throw SkyCatalogueError.noObjects(folder: folder.path) }
    guard let overlay = openNGCOverlay else { return catalogue }
    return catalogue.overlaid(with: try overlayEntries(contentsOf: overlay))
  }

  /// The catalogue folder of the Siril `environment` names: a symlinked `SIRIL_BIN`
  /// (`/usr/local/bin/siril-cli`) names the app's binary, hence its lists.
  package static func installedFolder(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL {
    let siril = SirilTool.path(environment: environment)
    return folder(sirilPath: URL(fileURLWithPath: siril).resolvingSymlinksInPath().path)
  }

  /// Where Siril keeps its lists, from the `siril-cli` path; a pure path function.
  ///
  /// Inside the app bundle (`…/Siril.app/Contents/Resources/share/siril/catalogue`), or beside the
  /// prefix's `share/` for a `bin/siril-cli` install. Nothing is read.
  package static func folder(sirilPath: String) -> URL {
    let binary = URL(fileURLWithPath: sirilPath)
    let macOS = binary.deletingLastPathComponent()
    let contents = macOS.deletingLastPathComponent()
    let resources =
      macOS.lastPathComponent == "MacOS" && contents.lastPathComponent == "Contents"
      ? contents.appendingPathComponent("Resources") : contents
    return resources.appendingPathComponent("share/siril/catalogue", isDirectory: true)
  }

  /// The lists under `folder` merged in `Source` order, then `overlay` laid over them.
  ///
  /// No overlay: no types nor common names. A missing list is skipped, as Siril builds may ship
  /// fewer.
  package static func load(folder: URL, overlay: URL? = openNGCOverlay) throws -> Self {
    var objects: [SkyObject] = []
    for source in SkyObject.Source.allCases {
      let file = folder.appendingPathComponent(source.file)
      guard FileManager.default.fileExists(atPath: file.path) else { continue }
      objects += try parse(read(file), source: source, file: source.file)
    }
    let catalogue = Self(objects: objects)
    guard let overlay else { return catalogue }
    return catalogue.overlaid(with: try overlayEntries(contentsOf: overlay))
  }

  /// The rows of one list: an unusable row (no name, a coordinate that is not a number) is skipped.
  static func parse(_ text: String, source: SkyObject.Source, file: String) throws -> [SkyObject] {
    let (columns, rows) = table(text)
    // An empty or header-only list is a list with no row, as the legacy parser took it.
    if rows.isEmpty { return [] }
    guard let name = columns["name"], let ra = columns["ra"], let dec = columns["dec"] else {
      throw SkyCatalogueError.missingColumns(file: file)
    }
    return rows.compactMap { row in
      let cell = { (index: Int?) in index.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
      guard !cell(name).isEmpty, let raDeg = number(cell(ra)), let decDeg = number(cell(dec))
      else { return nil }
      var object = SkyObject(
        name: cell(name), raDeg: raDeg, decDeg: decDeg, source: source,
        magnitude: number(cell(columns["mag"])), majorAxisArcmin: number(cell(columns["diameter"])))
      for alias in cell(columns["alias"]).split(separator: "/") { object.addAlias(String(alias)) }
      return object
    }
  }

  /// A CSV's header (lower-cased column → index) and its rows, cells trimmed.
  ///
  /// Siril's and OpenNGC's files quote nothing: a plain split is the whole format.
  static func table(_ text: String) -> (columns: [String: Int], rows: [[String]]) {
    let lines = text.split(whereSeparator: \.isNewline).map { line in
      line.split(separator: ",", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
    }
    guard let header = lines.first else { return ([:], []) }
    // A repeated column name keeps its last position, as the legacy `headerIndex`.
    let columns = Dictionary(
      header.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { _, last in last })
    return (columns, Array(lines.dropFirst()))
  }

  /// A cell's number; a blank, unparseable or non-finite cell (`nan`) is unknown.
  static func number(_ cell: String) -> Double? {
    Double(cell).flatMap { $0.isFinite ? $0 : nil }
  }

  /// The text of `file`.
  static func read(_ file: URL) throws -> String {
    do {
      return try String(contentsOf: file, encoding: .utf8)
    } catch {
      throw SkyCatalogueError.unreadable(file: file.path, reason: error.localizedDescription)
    }
  }
}
