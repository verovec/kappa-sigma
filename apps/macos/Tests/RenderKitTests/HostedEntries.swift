import AppKit
import Foundation
import RenderKit
import SwiftUI

/// What a view's controls announce (`AccessibilityAudit.Key`), read from an offscreen hosting
/// view after a layout and a turn of the run loop (the preference needs one to arrive — the
/// same turn `AccessibilityAuditTests` takes in the app tests).
@MainActor
enum HostedEntries {
  final class Reported {
    var entries: [AccessibilityAudit.Entry] = []
  }

  static func entries<Content: View>(
    of view: Content, language: String = "fr", width: CGFloat = 900, height: CGFloat = 1800
  ) -> [AccessibilityAudit.Entry] {
    let reported = Reported()
    let host = NSHostingView(
      rootView: view.environment(\.locale, Locale(identifier: language))
        .onPreferenceChange(AccessibilityAudit.Key.self) { reported.entries = $0 }
        .frame(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    return reported.entries
  }
}
