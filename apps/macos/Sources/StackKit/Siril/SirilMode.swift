/// How StackKit talks to Siril.
package enum SirilMode: Equatable, Sendable {
  /// One `siril-cli -s` process per script: the mode every oracle was recorded in.
  case script
  /// A long-lived `siril-cli -p` session (`SirilSession`).
  case pipe

  /// Pipe mode: the 0048 golden is byte-identical in both (`PreprocessLiveTests`).
  package static let `default` = Self.pipe
}
