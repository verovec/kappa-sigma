/// Why a Siril run or session failed, with what the user can act on.
package enum SirilError: Error, Equatable, Sendable {
  /// No `siril-cli` at the path (install card: the tool is missing, never a fallback, R2).
  case notInstalled(path: String)
  /// `--version` did not mention Siril.
  case notSiril(output: String)
  /// `--version` printed no version number.
  case unreadableVersion(output: String)
  /// Siril older than 1.4.
  case tooOld(version: String)
  /// A script exited non-zero; `hint` is the cause read from its log.
  case scriptFailed(exitCode: Int32, hint: String)
  /// A pipe-mode command answered `status: error`; `hint` is the cause from its log lines.
  case commandFailed(command: String, hint: String)
  /// The pipe-mode Siril died during `command`; a fresh instance was started, the caller
  /// resumes the step.
  case restarted(command: String)
  /// The session could not start (pipes or process).
  case sessionFailed(reason: String)
}
