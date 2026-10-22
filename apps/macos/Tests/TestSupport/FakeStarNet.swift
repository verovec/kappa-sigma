package import Foundation

/// StarNet2 played by a shell script (StarNet has no public licence, CI has none): it answers
/// `--machine-info` like StarNet2, prints its progress without line breaks and copies its input
/// TIFF to its output, so the « starless » is the image itself.
package enum FakeStarNet {
  /// The percentages the script prints, in order.
  package static let percents: [Double] = [0, 8.3, 50, 100]

  /// The script.
  package static let script = """
    #!/bin/sh
    if [ "$1" = "--machine-info" ]; then
      echo 'StarNet2 {"schema": "starnetastro.cli.machine-info/1", "version": "2.5"}'; exit 0
    fi
    [ "$1" = "-i" ] || { echo "positional arguments are not supported"; exit 2; }
    printf 'Working: 0.0%%Working: 8.3%%Working: 50.0%%'
    printf 'Working: 100.0%%Working: Done!\\n'
    cp "$2" "$4"
    """

  /// Writes the script as an executable `starnet2` in `folder` and returns its path.
  package static func install(in folder: URL) throws -> String {
    let url = folder.appendingPathComponent("starnet2")
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
  }
}
