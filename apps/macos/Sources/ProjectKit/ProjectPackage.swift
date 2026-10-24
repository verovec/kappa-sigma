public import Foundation
internal import GRDB

/// An AstroStack project on disk: a `.astrostack` folder holding `project.db` (design §4.5).
///
/// The database is edited in place through one `DatabasePool` (WAL) for as long as the package
/// is open; saving checkpoints the WAL so `project.db` alone holds every committed change.
/// `create` and `open` bring the schema to the latest migration (`Migrations/`, `SCHEMA.md`);
/// `store` is the typed access to it.
public final class ProjectPackage {
  /// The file name extension of a package.
  public static let fileExtension = "astrostack"
  /// The uniform type identifier the app exports for packages (`Info.plist`).
  package static let typeIdentifier = "fr.astrostack.project"
  /// The database file inside the package.
  private static let databaseName = "project.db"
  /// `PRAGMA application_id` of every project database: "ASTK".
  static let applicationID: Int32 = 0x4153_544B

  /// The folder the package lives in.
  public let url: URL
  /// Typed access to `project.db`.
  package let store: ProjectStore
  private let pool: DatabasePool

  /// Wraps an open pool and migrates it to the latest schema.
  private init(url: URL, pool: DatabasePool) throws {
    self.url = url
    self.pool = pool
    self.store = ProjectStore(pool: pool, migrations: try MigrationCatalog.bundled())
    try store.migrate(to: nil)
  }

  /// Creates a new package with an empty `project.db` at `url`; never overwrites anything.
  public static func create(at url: URL) throws -> ProjectPackage {
    let manager = FileManager.default
    guard !manager.fileExists(atPath: url.path) else {
      throw ProjectPackageError.alreadyExists(path: url.path)
    }
    try manager.createDirectory(at: url, withIntermediateDirectories: false)
    let pool = try DatabasePool(path: databaseURL(in: url).path)
    try pool.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA application_id = \(applicationID)")
    }
    let package = try ProjectPackage(url: url, pool: pool)
    // The id must reach the main file now: `open` reads it from there, even after a crash.
    try package.save()
    return package
  }

  /// Opens the package at `url`, refusing anything AstroStack did not create.
  public static func open(at url: URL) throws -> ProjectPackage {
    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
      throw ProjectPackageError.notAPackage(path: url.path)
    }
    let database = databaseURL(in: url)
    guard FileManager.default.fileExists(atPath: database.path) else {
      throw ProjectPackageError.missingDatabase(path: url.path)
    }
    guard try applicationID(of: database) == applicationID else {
      throw ProjectPackageError.foreignDatabase(path: url.path)
    }
    let pool = try DatabasePool(path: database.path)
    do {
      return try ProjectPackage(url: url, pool: pool)
    } catch {
      try? pool.close()
      throw error
    }
  }

  /// The counts of the package at `url`, read without opening it: a read-only connection that
  /// neither migrates, checkpoints nor removes the WAL, so a project open elsewhere is untouched.
  package static func readSummary(at url: URL) throws -> ProjectSummary {
    try readOnly(at: url, ProjectStore.summary(in:))
  }

  /// Runs `body` on a read-only connection to the package at `url`, which neither migrates,
  /// checkpoints nor removes the WAL: a project open elsewhere is untouched.
  static func readOnly<T>(at url: URL, _ body: (Database) throws -> T) throws -> T {
    let database = databaseURL(in: url)
    guard FileManager.default.fileExists(atPath: database.path) else {
      throw ProjectPackageError.missingDatabase(path: url.path)
    }
    guard try applicationID(of: database) == applicationID else {
      throw ProjectPackageError.foreignDatabase(path: url.path)
    }
    var configuration = Configuration()
    configuration.readonly = true
    // A closed package has no -wal/-shm, and SQLite cannot open a WAL database read-only without
    // creating them: it is then read as immutable. An open one keeps its own and is read live.
    let wal = FileManager.default.fileExists(atPath: database.path + "-wal")
    let path = wal ? database.path : database.absoluteString + "?immutable=1"
    let queue = try DatabaseQueue(path: path, configuration: configuration)
    defer { try? queue.close() }
    return try queue.read(body)
  }

  /// The application id in the SQLite file header, or 0 for an empty or non-SQLite file.
  ///
  /// Bytes 68–71, big-endian. Read from the bytes because any SQLite connection could change a
  /// foreign file (a pool switches it to WAL; a read-only one cannot open a WAL file alone).
  private static func applicationID(of database: URL) throws -> Int32 {
    let handle = try FileHandle(forReadingFrom: database)
    defer { try? handle.close() }
    let header = try handle.read(upToCount: 72) ?? Data()
    guard header.count == 72, header.starts(with: Data("SQLite format 3\0".utf8)) else {
      return 0
    }
    return Int32(bitPattern: header[68..<72].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
  }

  /// Makes `project.db` alone hold every committed change (WAL checkpoint, truncating).
  public func save() throws {
    try pool.writeWithoutTransaction { db in
      _ = try db.checkpoint(.truncate)
    }
  }

  /// Writes a copy of the package at `destination` (Save As); this package stays open here.
  ///
  /// The database goes through SQLite's online backup, the rest of the folder is copied as is.
  public func copy(to destination: URL) throws {
    let manager = FileManager.default
    guard !manager.fileExists(atPath: destination.path) else {
      throw ProjectPackageError.alreadyExists(path: destination.path)
    }
    try manager.createDirectory(at: destination, withIntermediateDirectories: false)
    do {
      try writeContents(to: destination)
    } catch {
      // Never leave a half-written package where the user asked for a copy.
      try? manager.removeItem(at: destination)
      throw error
    }
  }

  private func writeContents(to destination: URL) throws {
    let manager = FileManager.default
    for item in try manager.contentsOfDirectory(atPath: url.path)
    where !item.hasPrefix(Self.databaseName) {
      try manager.copyItem(
        at: url.appendingPathComponent(item), to: destination.appendingPathComponent(item))
    }
    let target = try DatabaseQueue(path: Self.databaseURL(in: destination).path)
    defer { try? target.close() }
    try pool.backup(to: target)
  }

  /// Checkpoints and closes the database, leaving `-wal` and `-shm` in place; the package must
  /// not be used afterwards.
  ///
  /// For a short background write to a project a window may open at the same moment (the
  /// retention review, card 0114): removing the WAL files under another connection could corrupt
  /// it, so they stay (emptied by the truncating checkpoint, `project.db` holding every change)
  /// for whoever closes the project last. A checkpoint another connection blocks stays passive.
  package func closeKeepingWAL() throws {
    // The pool closes even when both checkpoints fail: never a connection left behind.
    defer { try? pool.close() }
    try pool.writeWithoutTransaction { db in
      if (try? db.checkpoint(.truncate)) == nil { _ = try db.checkpoint(.passive) }
    }
  }

  /// Checkpoints and closes the database; the package must not be used afterwards.
  ///
  /// GRDB keeps the WAL persistent, so SQLite leaves `-wal` and `-shm` behind on close. Once the
  /// WAL is checkpointed empty they hold nothing: they are removed so that a closed package is
  /// one self-contained `project.db` (safe to copy in the Finder or back up). The pool is closed
  /// even when the checkpoint fails; the WAL then stays, and the checkpoint error is rethrown.
  public func close() throws {
    var checkpointError: (any Error)?
    do { try save() } catch { checkpointError = error }
    try pool.close()
    if let checkpointError { throw checkpointError }
    let manager = FileManager.default
    let wal = Self.databaseURL(in: url).path + "-wal"
    let walSize = (try? manager.attributesOfItem(atPath: wal)[.size] as? Int) ?? 0
    guard walSize == 0 else { return }
    for suffix in ["-wal", "-shm"] {
      let path = Self.databaseURL(in: url).path + suffix
      if manager.fileExists(atPath: path) { try manager.removeItem(atPath: path) }
    }
  }

  private static func databaseURL(in package: URL) -> URL {
    package.appendingPathComponent(databaseName)
  }
}
