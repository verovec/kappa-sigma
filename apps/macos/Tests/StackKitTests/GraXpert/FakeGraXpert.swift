import Foundation
import TestSupport

/// A stand-in `GraXpert.app`: its `Contents/MacOS/GraXpert` is a shell script reading the CLI the
/// runner emits (`<input> -cli -cmd … -output <stem> …`), printing two progress lines and copying
/// its input to `<stem>.<input extension>` as GraXpert 3.0 names its output (so a subtraction
/// leaves a zero model).
enum FakeGraXpert {
  static let script = """
    #!/bin/sh
    out=""; in=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -output) out="$2"; shift ;;
        -cli|-bg) ;;
        -cmd|-correction|-smoothing|-gpu) shift ;;
        *) in="$1" ;;
      esac
      shift
    done
    echo "INFO Background extraction 50%"
    echo "INFO Saving 100%"
    cp "$in" "$out.${in##*.}"
    """

  /// Installs an app bundle whose executable is `script`; returns the bundle path.
  static func install(in folder: URL, script: String = script, named name: String = "GraXpert.app")
    throws -> String
  {
    let app = folder.appendingPathComponent(name, isDirectory: true)
    let binaries = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
    let url = binaries.appendingPathComponent("GraXpert")
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return app.path
  }
}
