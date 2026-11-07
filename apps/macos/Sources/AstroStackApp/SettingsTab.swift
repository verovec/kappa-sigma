package import Foundation

/// One tab of the Settings window (card 0177): seven sections in one grouped form had no height
/// of their own, so the window opened as a title bar.
package enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
  /// The interface language.
  case general
  /// The scratch, astro and export folders.
  case folders
  /// The S3 connections.
  case s3
  /// The retention of stacks never exported.
  case storage
  /// The host tools' status.
  case tools

  package var id: String { rawValue }

  /// The tab's title.
  package var title: LocalizedStringResource {
    switch self {
    case .general: .app("General")
    case .folders: .app("Folders")
    case .s3: .app("S3 connections")
    case .storage: .app("Storage")
    case .tools: .app("Tools")
    }
  }

  /// The tab's SF Symbol.
  package var symbol: String {
    switch self {
    case .general: "gearshape"
    case .folders: "folder"
    case .s3: "externaldrive.connected.to.line.below"
    case .storage: "internaldrive"
    case .tools: "wrench.and.screwdriver"
    }
  }

  /// The width of every tab's form.
  package static let formWidth: CGFloat = 460
  /// The least height of every tab's form, so a short tab never shrinks the window around it.
  package static let formMinHeight: CGFloat = 400
}
