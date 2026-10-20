internal import Foundation

/// Checks a module against `BoundaryRules`: declared dependencies within its allow-list, nothing
/// depends on the app, a `<Module>Tests` target exists, UI frameworks imported only where allowed.
package enum ModuleBoundary {
  private static let uiFrameworks: Set<String> = ["SwiftUI", "AppKit"]

  /// The violations of `module`, given the manifest's targets and the module's sources
  /// (file name → text).
  package static func violations(
    module: String, targets: [DeclaredTarget], sources: [String: String], rules: BoundaryRules
  ) -> [BoundaryViolation] {
    guard let target = targets.first(where: { $0.name == module }) else {
      return [BoundaryViolation(description: "\(module) is not declared in Package.swift")]
    }
    var found = dependencyViolations(of: target, rules: rules)
    if !targets.contains(where: { $0.name == "\(module)Tests" && $0.kind == .test }) {
      found.append(BoundaryViolation(description: "\(module) has no test target"))
    }
    if !rules.uiModules.contains(module) {
      found += importViolations(module: module, sources: sources)
    }
    return found
  }

  /// The directory holding `Package.swift`, found by walking up from a source file.
  package static func packageRoot(from filePath: String) throws -> String {
    var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    while url.path != "/" {
      if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
        return url.path
      }
      url.deleteLastPathComponent()
    }
    throw ModuleBoundaryError.packageNotFound(from: filePath)
  }

  /// Checks `module` of this package against `BoundaryRules.astroStack`.
  package static func check(module: String, filePath: String = #filePath) throws
    -> [BoundaryViolation]
  {
    let root = URL(fileURLWithPath: try packageRoot(from: filePath))
    let manifest = try String(
      contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
    return violations(
      module: module, targets: ManifestParser.targets(in: manifest),
      sources: try swiftSources(in: root.appendingPathComponent("Sources/\(module)")),
      rules: .astroStack)
  }

  // MARK: - Rules

  private static func dependencyViolations(of target: DeclaredTarget, rules: BoundaryRules)
    -> [BoundaryViolation]
  {
    guard let allowed = rules.allowedDependencies[target.name] else {
      return [BoundaryViolation(description: "\(target.name) has no allow-list entry")]
    }
    return target.dependencies.compactMap { dependency in
      if dependency == rules.appModule {
        return BoundaryViolation(description: "\(target.name) depends on \(dependency)")
      }
      guard allowed.contains(dependency) else {
        return BoundaryViolation(
          description: "\(target.name) depends on \(dependency) (not allowed)")
      }
      return nil
    }
  }

  private static func importViolations(module: String, sources: [String: String])
    -> [BoundaryViolation]
  {
    sources.keys.sorted().flatMap { file in
      importedModules(in: sources[file] ?? "")
        .filter { uiFrameworks.contains($0.module) }
        .map {
          BoundaryViolation(description: "\(module) imports \($0.module) (\(file):\($0.line))")
        }
    }
  }

  /// The module of every `import` line, with its 1-based line number.
  private static func importedModules(in source: String) -> [(module: String, line: Int)] {
    source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
      .compactMap { offset, line in
        let words = line.split(whereSeparator: \.isWhitespace).filter {
          !$0.hasPrefix("@") && !accessModifiers.contains(String($0))
        }
        guard words.count >= 2, words[0] == "import" else { return nil }
        let kinds: Set<String> = ["class", "struct", "enum", "func", "protocol", "typealias"]
        let path = kinds.contains(String(words[1])) && words.count > 2 ? words[2] : words[1]
        let module = path.split(separator: ".").first.map(String.init) ?? String(path)
        return (module, offset + 1)
      }
  }

  private static let accessModifiers: Set<String> = [
    "public", "package", "internal", "fileprivate", "private",
  ]

  private static func swiftSources(in directory: URL) throws -> [String: String] {
    guard let walker = FileManager.default.enumerator(atPath: directory.path) else { return [:] }
    var sources: [String: String] = [:]
    for case let relative as String in walker where relative.hasSuffix(".swift") {
      sources[relative] = try String(
        contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
    }
    return sources
  }
}
