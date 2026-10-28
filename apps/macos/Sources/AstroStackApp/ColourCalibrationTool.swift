package import Foundation
internal import ImageKit
package import ProcessKit
package import StackKit

/// The colour-calibration process's tool (card 0094): the panel's values as a
/// `ColourCalibrationRequest`, Siril's SPCC or PCC on the head, Siril's pixels back with the
/// factors it applied.
package nonisolated enum ColourCalibrationTool {
  /// The request the panel's `params` give, every value as shown: the mono route when its
  /// `camera` is mono (card 0140).
  package static func request(_ params: ParamSet) -> ColourCalibrationRequest {
    let reference = params.choice("whiteReference")
    let method: ColourCalibrationRequest.Method =
      if params.choice("method") == "pcc" {
        .pcc
      } else if ColourCalibrationProcess.isMono(params) {
        .monoSPCC(
          sensor: params.choice("monoSensor"), red: params.choice("rFilter"),
          green: params.choice("gFilter"), blue: params.choice("bFilter"),
          whiteReference: reference)
      } else {
        .spcc(
          sensor: params.choice("sensor"), filter: params.choice("filter"),
          whiteReference: reference)
      }
    let limit = params.number("limitMag")
    return ColourCalibrationRequest(
      method: method, limitMag: limit > 0 ? limit : nil,
      backgroundTolerance: (params.number("bgTolBelow"), params.number("bgTolAbove")),
      catalogue: PlateSolveRequest.Catalogue(rawValue: params.choice("catalogue")) ?? .localGaia)
  }

  /// The tool over `calibrator` (built at each Apply: Siril is located then).
  package static func tool(
    scratch: URL, calibrator: @escaping @Sendable () throws -> ColourCalibrator
  ) -> StudioTool {
    StudioTool { image, params, onProgress in
      let request = request(params)
      let calibrated = try await calibrator().calibrate(
        image, request: request, scratch: scratch, onProgress: onProgress)
      let (report, pcc) = (calibrated.report, request.method == .pcc)
      return StudioToolResult(image: calibrated.image) { Self.report(report, pcc: pcc, locale: $0) }
    }
  }

  /// The tool over the installed Siril and the local catalogues of the astro library.
  package static func live(scratch: URL) -> StudioTool {
    tool(scratch: scratch) {
      ColourCalibrator.live(
        binary: try SirilTool.locate(), support: PlateSolver.supportFolder,
        catalogues: AstroFolderSetting().catalogues)
    }
  }

  /// What Siril applied, as the panel says it (with Siril's own warning, when it gave one).
  package static func report(_ report: ColourCalibrationReport, pcc: Bool, locale: Locale)
    -> LocalizedStringResource
  {
    let format = AstroFormat(locale: locale)
    // Channel letters and × read alike in both languages.
    let factors = zip(["R", "G", "B"], report.factors)
      .map { "\($0) × \(format.parameter($1))" }.joined(separator: ", ")
    let method = pcc ? "PCC" : "SPCC"
    // No count shown when Siril printed none (R2: never a value it did not give).
    guard let stars = report.stars else {
      return report.warnings.isEmpty
        ? .app("\(method): \(factors).", locale: locale)
        : .app(
          "\(method): \(factors); imprecise fit, extract the background first.", locale: locale)
    }
    if report.warnings.isEmpty {
      return .app("\(method): \(factors), from \(stars) stars.", locale: locale)
    }
    return .app(
      "\(method): \(factors), from \(stars) stars; imprecise fit, extract the background first.",
      locale: locale)
  }
}
