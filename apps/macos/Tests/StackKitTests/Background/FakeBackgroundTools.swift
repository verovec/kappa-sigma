import Foundation
import StackKit
import Synchronization
import TestSupport

/// Counting stand-ins for the two engines: GraXpert as the fake app (copies input to output),
/// Siril as a closure playing `load X … save Y` by copying `X.fits` to `Y.fits` in the directory.
final class FakeBackgroundTools: Sendable {
  let graxpertCalls = Mutex(0)
  let sirilCalls = Mutex(0)
  let scripts = Mutex<[SirilScript]>([])

  /// Siril's file side: copies the loaded image to the saved name, untouched.
  var siril: SirilRunner {
    SirilRunner { script, directory, onLine in
      self.sirilCalls.withLock { $0 += 1 }
      self.scripts.withLock { $0.append(script) }
      var loaded: String?
      for command in script.commands {
        switch command {
        case .load(let name): loaded = name
        case .save(let name):
          guard let loaded else { continue }
          try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(name).fits"))
          try FileManager.default.copyItem(
            at: directory.appendingPathComponent("\(loaded).fits"),
            to: directory.appendingPathComponent("\(name).fits"))
        default: break
        }
        onLine(SirilLine(parsing: "log: \(command.line)"))
      }
      return ""
    }
  }

  /// The fake GraXpert app, counted.
  func graxpert(in folder: URL) throws -> GraXpertRunner {
    let live = GraXpertRunner.live(app: try FakeGraXpert.install(in: folder))
    return GraXpertRunner { input, output, options, onProgress in
      self.graxpertCalls.withLock { $0 += 1 }
      return try await live.run(input, output, options, onProgress)
    }
  }
}
