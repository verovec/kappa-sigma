package import ProjectKit

/// A process as the kernel knows it: ProjectKit's `ProcessStamp` (card 0147) — pid and start
/// time, the one rule; `owner.json` keeps its bytes (same keys).
package typealias ProcessIdentity = ProcessStamp
