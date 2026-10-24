internal import ProjectKit
internal import RenderKit
internal import SwiftUI

/// The Données stage's Storage section (card 0114).
///
/// Every stack with its size on disk, its exports and when the Studio last opened it, and Delete.
/// Nothing goes without a confirmation naming the size (R2); the stack the Studio shows cannot be
/// deleted.
struct StackStorageView: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale
  @State private var confirming: StackStorageRow?

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      SectionHeader(
        .app("Storage"),
        detail: .app("Each stack and its Studio history, measured on disk."),
        help: StageHelp.help(.data, locale: locale))
      ForEach(model.storage) { row in
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading) {
            Text(verbatim: model.stackLabel(row.stack, locale: locale))
            Text(details(row)).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Text(verbatim: size(row.bytes)).monospacedDigit()
          deleteButton(row)
        }
      }
    }
    .task(id: model.stacks.map(\.id)) { await model.listStorage() }
    .confirmationDialog(
      Text(.app("Delete this stack?")),
      isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
      presenting: confirming
    ) { row in
      Button(.app("Delete \(size(row.bytes))"), role: .destructive) {
        Task { await model.deleteStack(row.id) }
      }
      Button(.app("Cancel"), role: .cancel) {}
    } message: { row in
      let amount = size(row.bytes)
      if row.exports > 0 {
        Text(.app("\(amount) go with its history and export records; exported files stay."))
      } else {
        Text(
          .app("\(amount) leave the disk with its Studio history; this cannot be undone."))
      }
    }
  }

  @ViewBuilder private func deleteButton(_ row: StackStorageRow) -> some View {
    let open = model.isStackOpen(row.id)
    Button(.app("Delete…"), role: .destructive) { confirming = row }
      .disabled(open || model.isStacking)
      .help(open ? Text(.app("The Studio shows this stack.")) : Text(verbatim: ""))
      .accessible(.dataDeleteStack(row.id), label: .app("Delete…"))
  }

  /// « exported 2× · last opened … » or « never exported · never opened ».
  private func details(_ row: StackStorageRow) -> LocalizedStringResource {
    let opened = row.stack.openedAt.map {
      Date(timeIntervalSince1970: Double($0) / 1000)
        .formatted(.dateTime.locale(locale).year().month().day())
    }
    switch (row.exports, opened) {
    case (0, nil): return .app("never exported · never opened in the Studio")
    case (0, let date?): return .app("never exported · last opened \(date)")
    case (let count, nil): return .app("exported \(count)× · never opened in the Studio")
    case (let count, let date?): return .app("exported \(count)× · last opened \(date)")
    }
  }

  private func size(_ bytes: Int64) -> String {
    AstroFormat(locale: locale).bytes(bytes)
  }
}
