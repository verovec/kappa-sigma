package import Foundation
internal import RenderKit
package import SwiftUI

/// Settings › S3 connections (card 0150): the named connections, the one being edited, and a
/// « Test » that lists a bucket with a connection's keys.
///
/// The secret is typed in a `SecureField` and never shown back: a stored one reads « •••• ».
package struct S3ConnectionsSection: View {
  @Bindable private var model: S3ConnectionsModel
  @Environment(\.locale) private var locale
  /// The connection whose Remove waits for confirmation: its secret goes with it, for good.
  @State private var removing: S3Connection?

  /// The section over `model`.
  package init(model: S3ConnectionsModel) { self.model = model }

  package var body: some View {
    Section {
      if model.connections.isEmpty && model.draft == nil {
        Text(.app("No connection yet: add one for remote captures or S3 exports."))
          .font(.caption).foregroundStyle(.secondary)
      }
      ForEach(model.connections) { connection in row(connection) }
      if let draft = model.draft {
        editor(isNew: draft.isNew)
      } else {
        HStack {
          Spacer()
          Button(.app("Add…")) { model.add() }
        }
      }
      if let refusal = model.refusal {
        Text(refusal.message).font(.caption).foregroundStyle(DesignColor.statusError.color)
      }
      if !model.connections.isEmpty { testLine }
    } header: {
      SectionHeader(
        .app("S3 connections"), help: SettingHelp.help(SettingHelp.s3Connections, locale: locale))
    }
    .onAppear { model.refreshSecretStates() }
  }

  private func row(_ connection: S3Connection) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: connection.name)
        Text(verbatim: "\(connection.endpoint) · \(connection.accessKey)")
          .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        secretLine(model.secretStates[connection.id] ?? .missing)
      }
      Spacer()
      Button(.app("Edit…")) { model.edit(connection.id) }.disabled(model.draft != nil)
      Button(.app("Remove…")) { removing = connection }.disabled(model.draft != nil)
    }
    .confirmationDialog(
      Text(.app("Remove this connection and its secret?")),
      isPresented: Binding(
        get: { removing?.id == connection.id }, set: { if !$0 { removing = nil } })
    ) {
      Button(.app("Remove"), role: .destructive) { model.remove(connection.id) }
    } message: {
      Text(.app("The secret leaves the Keychain; projects using this connection lose it."))
    }
  }

  @ViewBuilder
  private func secretLine(_ state: S3ConnectionStore.SecretState) -> some View {
    switch state {
    case .stored:
      Text(.app("Secret •••• stored in the Keychain")).font(.caption).foregroundStyle(.secondary)
    case .missing:
      Text(.app("Secret missing: edit the connection to enter it."))
        .font(.caption).foregroundStyle(DesignColor.statusError.color)
    case .unreadable(let error):
      Text(UserFacingError.s3Connection(.keychain(error)).message)
        .font(.caption).foregroundStyle(DesignColor.statusError.color)
    }
  }

  @ViewBuilder
  private func editor(isNew: Bool) -> some View {
    TextField(.app("Name"), text: field(\.connection.name))
    TextField(.app("Endpoint"), text: field(\.connection.endpoint))
    TextField(.app("Region"), text: field(\.connection.region), prompt: Text(verbatim: "us-east-1"))
    Toggle(isOn: pathStyle) { Text(.app("Path-style addressing")) }
    Text(.app("MinIO, Garage: on; AWS: off."))
      .font(.caption).foregroundStyle(.secondary)
    TextField(.app("Access key"), text: field(\.connection.accessKey))
    SecureField(text: field(\.secret)) { Text(.app("Secret key")) }
    if !isNew {
      Text(.app("Leave empty to keep the secret stored in the Keychain."))
        .font(.caption).foregroundStyle(.secondary)
    }
    HStack {
      Spacer()
      Button(.app("Cancel")) { model.cancel() }
      Button(.app("Save")) { model.save() }.keyboardShortcut(.defaultAction)
    }
  }

  private var testLine: some View {
    Group {
      Picker(selection: $model.testConnection) {
        ForEach(model.connections) { Text(verbatim: $0.name).tag(Optional($0.id)) }
      } label: {
        Text(.app("Connection"))
      }
      HStack {
        TextField(.app("Bucket"), text: $model.testBucket)
        TextField(.app("Prefix"), text: $model.testPrefix)
        Button(.app("Test")) { Task { await model.test() } }.disabled(!model.canTest)
      }
      if let result = model.testResult {
        Text(Self.result(result)).font(.caption).textSelection(.enabled)
          .foregroundStyle(Self.isFailure(result) ? DesignColor.statusError.color : .secondary)
      }
    }
  }

  private func field(_ path: WritableKeyPath<S3ConnectionsModel.Draft, String>) -> Binding<String> {
    Binding(
      get: { model.draft?[keyPath: path] ?? "" },
      set: { model.draft?[keyPath: path] = $0 })
  }

  private var pathStyle: Binding<Bool> {
    Binding(
      get: { model.draft?.connection.pathStyle ?? false },
      set: { model.draft?.connection.pathStyle = $0 })
  }

  // MARK: - Result line

  /// What the Test line says; a failure is the service's (or the system's) own text.
  package static func result(_ result: S3ConnectionsModel.TestResult) -> LocalizedStringResource {
    switch result {
    case .running: .app("Testing…")
    case .ok(let count) where count >= S3ConnectionsModel.testLimit:
      .app("OK — at least \(count) objects seen")
    case .ok(let count): .app("OK — \(count) objects seen")
    case .failed(let text): .app("\(text)")
    case .secretMissing: .app("No secret stored for this connection: edit it to enter one.")
    case .noConnection: .app("Choose a connection to test.")
    }
  }

  /// The Test line resolved in `locale` (tests read it).
  package static func resultLine(_ result: S3ConnectionsModel.TestResult, locale: Locale)
    -> String
  {
    var resource = Self.result(result)
    resource.locale = locale
    return String(localized: resource)
  }

  private static func isFailure(_ result: S3ConnectionsModel.TestResult) -> Bool {
    switch result {
    case .failed, .secretMissing, .noConnection: true
    case .running, .ok: false
    }
  }
}
