/// A command line found in a captured script (`setref …`, `unselect …`), with its script name.
package struct OracleScriptCommand: Decodable, Equatable, Sendable {
  /// The captured script's file name.
  package let script: String
  /// The command, trimmed.
  package let command: String
}
