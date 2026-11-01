package import Foundation
package import ProcessKit

// MARK: - Where the export goes (card 0151)

extension ExportStageModel {
  /// What the template's tokens stand for in the next export: the stack's object (else the
  /// project's name), its bundle folder, the project where its package is now, the stamp.
  var templateValues: ExportPathTemplate.Values {
    let project = packageFolder().deletingPathExtension().lastPathComponent
    return ExportPathTemplate.Values(
      object: stack.object, stack: URL(fileURLWithPath: stack.bundlePath).lastPathComponent,
      project: project, date: stamp, zone: services.timeZone)
  }

  /// Where the next export writes: the base plus the template resolved — the path shown is the
  /// path written (R2); `nil` when the template names no folder (`folderRefusal` says why).
  package var folder: URL? {
    try? ExportPathTemplate(template).folder(under: base, templateValues)
  }

  /// Why the template names no folder, or `nil`.
  package var folderRefusal: ExportPathTemplate.Refusal? {
    ExportPathTemplate(template).refusal(templateValues)
  }

  /// The folder of the next export, or why nothing may be written: the template, the read-only
  /// sources (R7), a missing base that is not the app's to create, a base « Remember » refuses.
  func destinationCheck(astro: URL) -> Result<URL, UserFacingError> {
    let base = self.base
    let folder: URL
    do {
      folder = try ExportPathTemplate(template).folder(under: base, templateValues)
    } catch {
      return .failure(.exportTemplate(error))
    }
    guard ExportGuard.refusal(for: folder, astro: astro) == nil else {
      return .failure(.exportReadOnlyFolder(path: folder.path))
    }
    // Every export, remembered or not: never into a project nor a folder the sweep empties.
    let destination = services.destination
    if let refusal = destination.placeRefusal(for: folder) {
      return .failure(.exportBaseRefused(path: folder.path, refusal))
    }
    guard AstroFolderSetting.isFolder(base) || destination.mayCreate(base) else {
      return .failure(.exportFolderMissing(path: base.path))
    }
    return .success(folder)
  }

  /// After a written export with « Remember as default »: Settings takes its base and template.
  ///
  /// The base is there now and its place was checked by `destinationCheck`; the default base
  /// stays the default (nothing stored). Returns why the base was not kept, or `nil`.
  func rememberDestination() -> UserFacingError? {
    guard remember else { return nil }
    let destination = services.destination
    let refused = destination.isDefault(base) ? destination.choose(nil) : destination.choose(base)
    if let refused { return .exportBaseRefused(path: base.path, refused) }
    destination.choose(template: template)
    destination.choose(local: local, s3: s3)
    return nil
  }
}
