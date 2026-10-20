import Foundation

/// A stand-in `siril-cli` written as a shell script, speaking both modes the driver uses:
/// `-s script` (prints each line as `log:`; a line containing `fail` exits 1) and
/// `-p -r in -w out` (pipe mode: `ready`, then per command `status: starting`, progress, log,
/// `status: success`; `fail…` answers `status: error`; `boom…` dies mid-command).
enum FakeSiril {
  static let script = #"""
    #!/bin/bash
    if [ "${1:-}" = "--version" ]; then echo "siril 1.4.4"; exit 0; fi
    mode=""; in=""; out=""; file=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -p) mode=pipe ;;
        -r) in="$2"; shift ;;
        -w) out="$2"; shift ;;
        -s) mode=script; file="$2"; shift ;;
      esac
      shift
    done
    if [ "$mode" = script ]; then
      status=0
      while IFS= read -r line; do
        echo "log: $line"
        case "$line" in *fail*) echo "log: Error in line 4: '$line'."; status=1 ;; esac
      done < "$file"
      echo "progress: Script execution finished, 100%"
      exit $status
    fi
    exec 3<"$in"
    exec 4>"$out"
    echo "ready" >&4
    while IFS= read -r cmd <&3; do
      verb="${cmd%% *}"
      echo "status: starting $verb" >&4
      case "$verb" in
        boom) echo "log: about to crash" >&4; exit 3 ;;
        fail)
          echo "log: Error in line 1: 'fail' could not run" >&4
          echo "status: error $verb" >&4 ;;
        quiet)
          echo "log: Commande inconnue : 'quiet' ou pas encore implémentée" >&4
          echo "status: error $verb" >&4 ;;
        exit) exit 0 ;;
        slow)
          sleep 2
          echo "log: slow done" >&4
          echo "status: success $verb" >&4 ;;
        *)
          echo "progress: $verb, 50%" >&4
          echo "log: done $cmd" >&4
          echo "status: success $verb" >&4 ;;
      esac
    done
    """#

  /// A variant of the fake.
  enum Variant {
    /// Speaks the protocol.
    case normal
    /// Reports Siril 1.2.6 (below the floor).
    case old
    /// Never says `ready` in pipe mode.
    case silent
  }

  /// Writes the fake into `folder` and returns its path.
  static func install(in folder: URL, _ variant: Variant = .normal) throws -> String {
    let url = folder.appendingPathComponent("siril-cli")
    var text = script
    switch variant {
    case .normal: break
    case .old: text = text.replacingOccurrences(of: "siril 1.4.4", with: "siril 1.2.6")
    case .silent: text = text.replacingOccurrences(of: "echo \"ready\" >&4", with: "sleep 30")
    }
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
  }
}
