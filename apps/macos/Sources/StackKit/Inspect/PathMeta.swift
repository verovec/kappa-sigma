internal import Foundation

/// What a capture's file and folder names say (`internal/inspect/filename.go`), for the many
/// programs that omit IMAGETYP/FILTER, e.g.
///
/// `Light_ASIImg_30sec_Bin1_filter-B_-20.0C_gain300_2025-03-27_234852_frame0001.fit`. It only ever
/// fills what the header lacked.
package struct PathMeta: Equatable, Sendable {
  package var type: FrameType
  package var filter: String
  package var exposureMs: Int
  package var gain: Int
  package var tempMilliC: Int
  package var hasTemp: Bool
  package var bin: Int
  /// EFW slot from a SharpCap name (`2021-08-14-0047_6-1-CapObj_0000.FIT` → 1); 0 = none.
  package var wheelSlot: Int

  /// A value with the given fields, the rest at zero.
  package init(
    type: FrameType = .unknown, filter: String = "", exposureMs: Int = 0, gain: Int = 0,
    tempMilliC: Int = 0, hasTemp: Bool = false, bin: Int = 0, wheelSlot: Int = 0
  ) {
    self.type = type
    self.filter = filter
    self.exposureMs = exposureMs
    self.gain = gain
    self.tempMilliC = tempMilliC
    self.hasTemp = hasTemp
    self.bin = bin
    self.wheelSlot = wheelSlot
  }

  /// Parses the file name of `path` and its parent folder names (`parseFilenameMeta`).
  package init(path: String) {
    let name = Self.baseName(path)
    let low = name.lowercased()
    self.init(type: Self.typeFromToken(low))
    if type == .unknown { type = Self.typeFromFolders(path) }
    if let match = name.firstMatch(of: /(?i)filter[-_]([A-Za-z0-9]+)/) {
      filter = Filter.normalize(String(match.1))
    } else {
      filter = Self.filterFromFolders(path)
    }
    if let match = low.firstMatch(of: /(\d*\.?\d+)\s*sec/), let seconds = Double(match.1) {
      exposureMs = Int((seconds * 1000).rounded())
    }
    gain = Self.gain(inName: low) ?? Self.gainFromFolders(path)
    if let match = name.firstMatch(of: /(-?\d+\.?\d*)C(?:_|\.|$)/), let celsius = Double(match.1) {
      tempMilliC = Int((celsius * 1000).rounded())
      hasTemp = true
    }
    if let match = low.firstMatch(of: /bin(\d+)/) { bin = Int(match.1) ?? 0 }
    if let match = name.firstMatch(of: /^\d{4}-\d{2}-\d{2}-\d{4}_\d+-(\d+)-/) {
      wheelSlot = Int(match.1) ?? 0
    }
  }

  private static func typeFromToken(_ low: String) -> FrameType {
    if low.contains("flat") && low.contains("dark") { return .darkFlat }
    if low.hasPrefix("light") { return .light }
    if low.hasPrefix("dark") { return .dark }
    if low.hasPrefix("flat") { return .flat }
    if low.hasPrefix("bias") || low.hasPrefix("offset") { return .bias }
    return .unknown
  }
}
