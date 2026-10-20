import Foundation
import PackagePlugin

/// Compiles a target's `Localizable.xcstrings` into `en.lproj`/`fr.lproj` resources (card 0073).
///
/// The catalog is excluded from the target's resources so no toolchain compiles it a second
/// time; the generated `.lproj` folders become the target's localized resources on CLT and
/// Xcode alike. The languages are `StringCatalog.languages` (a plugin cannot import a library).
@main
struct CatalogPlugin: BuildToolPlugin {
  private static let languages = ["en", "fr"]

  func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
    let catalog = target.directoryURL.appending(path: "Localizable.xcstrings")
    let folder = context.pluginWorkDirectoryURL.appending(path: "Catalog")
    let outputs = Self.languages.flatMap { language in
      ["strings", "stringsdict"].map {
        folder.appending(path: "\(language).lproj/Localizable.\($0)")
      }
    }
    return [
      .buildCommand(
        displayName: "Compiling the string catalog of \(target.name)",
        executable: try context.tool(named: "CatalogTool").url,
        arguments: [catalog.path(percentEncoded: false), folder.path(percentEncoded: false)],
        inputFiles: [catalog], outputFiles: outputs)
    ]
  }
}
