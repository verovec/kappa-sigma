/// How the model leaves the image: taken away or divided out.
///
/// Subtraction suits a gradient the sky added, division a vignetting-like fall-off. The Siril
/// engines subtract only; GraXpert does both.
package enum BackgroundCorrection: String, CaseIterable, Hashable, Sendable {
  case subtract, divide

  /// GraXpert's `-correction` word.
  package var graxpertArgument: String {
    switch self {
    case .subtract: "Subtraction"
    case .divide: "Division"
    }
  }
}
