/// CPU and memory caps injected into a script (`Limits.apply`); zero values change nothing,
/// which is how every oracle was recorded.
package struct SirilLimits: Equatable, Sendable {
  /// `setcpu N` when > 0.
  package var maxCPUs: Int
  /// `setmem R` (fraction of RAM, two decimals) when > 0.
  package var memoryRatio: Double

  /// Limits; the defaults change nothing.
  package init(maxCPUs: Int = 0, memoryRatio: Double = 0) {
    self.maxCPUs = maxCPUs
    self.memoryRatio = memoryRatio
  }

  /// `script` with the limit commands right after its first line, if it starts with `requires `.
  package func apply(to script: String) -> String {
    guard maxCPUs > 0 || memoryRatio > 0, script.hasPrefix("requires "),
      let newline = script.firstIndex(of: "\n")
    else { return script }
    var inserted = ""
    if maxCPUs > 0 { inserted += "setcpu \(maxCPUs)\n" }
    if memoryRatio > 0 { inserted += "setmem \(GoFormat.fixed(memoryRatio, decimals: 2))\n" }
    let head = script[...newline]
    return head + inserted + script[script.index(after: newline)...]
  }
}
