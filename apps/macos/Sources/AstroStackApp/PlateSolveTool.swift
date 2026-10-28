package import Foundation
internal import ImageKit
package import ProcessKit
package import StackKit

/// The plate-solve process's tool (card 0093): the panel's values read as a `PlateSolveRequest`,
/// Siril's `PlateSolver` run on the head, the head back with the solution's WCS.
package nonisolated enum PlateSolveTool {
  /// A value Apply cannot solve with: refused before Siril runs, never filled in (R2).
  package enum InputError: Error, Equatable, Sendable {
    /// Right ascension or declination empty.
    case coordinatesMissing
    /// A coordinate that reads as neither sexagesimal nor degrees.
    case unreadable(String)
    /// Focal length or pixel size left at 0.
    case opticsMissing
  }

  /// The request the panel's `params` give.
  package static func request(_ params: ParamSet) throws -> PlateSolveRequest {
    let (raText, decText) = (
      params.text("ra").trimmingCharacters(in: .whitespacesAndNewlines),
      params.text("dec").trimmingCharacters(in: .whitespacesAndNewlines)
    )
    guard !raText.isEmpty, !decText.isEmpty else { throw InputError.coordinatesMissing }
    guard let ra = TargetCoordinates.rightAscension(raText), (0..<360).contains(ra) else {
      throw InputError.unreadable(raText)
    }
    guard let dec = TargetCoordinates.declination(decText), (-90...90).contains(dec) else {
      throw InputError.unreadable(decText)
    }
    let (focal, pixel) = (params.number("focalMm"), params.number("pixelSizeUm"))
    guard focal > 0, pixel > 0 else { throw InputError.opticsMissing }
    let limit = params.number("limitMag")
    return PlateSolveRequest(
      raDegrees: ra, decDegrees: dec, focalMm: focal, pixelSizeUm: pixel,
      limitMag: limit > 0 ? limit : nil,
      catalogue: PlateSolveRequest.Catalogue(rawValue: params.choice("catalogue")) ?? .localGaia)
  }

  /// The tool over `solver` (built at each Apply: Siril is located then), working in `scratch`.
  package static func tool(
    scratch: URL, solver: @escaping @Sendable () throws -> PlateSolver
  ) -> StudioTool {
    StudioTool { image, params, onProgress in
      let request = try request(params)
      let solved = try await solver().solve(
        AstroImage(
          width: image.width, height: image.height, planes: image.planes,
          metadata: image.metadata),
        request: request, scratch: scratch, onProgress: onProgress)
      image.metadata.wcs = solved.wcs
      let solution = solved.solution
      return StudioToolResult(image: image) { report(solution, locale: $0) }
    }
  }

  /// The tool over the installed Siril and the local catalogues of the astro library.
  package static func live(scratch: URL) -> StudioTool {
    tool(scratch: scratch) {
      PlateSolver.live(
        binary: try SirilTool.locate(), support: PlateSolver.supportFolder,
        catalogues: AstroFolderSetting().catalogues)
    }
  }

  /// The solution as the panel says it.
  package static func report(_ solution: PlateSolution, locale: Locale)
    -> LocalizedStringResource
  {
    let format = AstroFormat(locale: locale)
    let center =
      format.rightAscension(degrees: solution.centerRA) + " "
      + format.declination(degrees: solution.centerDec)
    let scale = format.parameter(solution.scaleArcsecPerPx)
    let rotation = format.parameter(solution.rotationDeg)
    let catalogue = solution.catalogue ?? "?"
    return .app(
      "Solved: centre \(center), \(scale)″/px, up \(rotation)° from north, \(catalogue).",
      locale: locale)
  }
}
