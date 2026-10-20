/// How a scan records colour (`inspect.ColorModel`), decided once from the lights.
package enum ColorModel: String, Codable, Sendable {
  /// A mono sensor behind a filter wheel; the default without colour evidence.
  case mono
  /// One-shot colour: every light carries the three primaries.
  case osc
  /// Both; no single run can stack them.
  case mixed
}
