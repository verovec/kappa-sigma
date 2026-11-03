internal import Foundation
internal import ProjectKit
package import StackKit

// MARK: - The Import sheet: opening it, and recording what it added

extension ProjectWindowModel {
  /// Opens the Import sheet on a fresh request.
  package func startImport() {
    closeImport()
    importError = nil
    let services = services(store())
    let profiles = ImportViewModel.profiles(store: store())
    importing = ImportViewModel(
      planning: services.planning, masters: services.masters, profiles: profiles.profiles,
      rejectedProfiles: profiles.rejected, remotePlanning: services.remotePlanning,
      bucket: services.browsing.map {
        // The connections as Settings holds them now: a sheet opened later sees a new one.
        ImportBucketModel(connections: S3ConnectionStore().connections, browsing: $0)
      })
  }

  /// Closes the Import sheet and stops its scan, which would otherwise run on for minutes.
  package func closeImport() {
    importing?.cancel()
    importing = nil
  }

  /// Records the imported folders as read-only sources of the project and closes the sheet; the
  /// next run applies the request's overrides.
  ///
  /// Recording is idempotent per folder: after a failure part-way, Add again records the rest.
  /// A night added through the sheet to a project that has some is followed by a rescan of them
  /// all (card 0100); any other plan the window cannot adopt waits for the user's Rescan.
  package func add(_ request: ImportRequest) {
    guard let store = store() else {
      error = .projectClosed
      importError = error
      return
    }
    let isNewNight = addsANight(request)
    var recorded = 0
    do {
      let remote = importing?.remoteTarget
      for path in request.paths {
        // A bucket prefix is the source it is (card 0168): recording it as a night would read
        // `s3://` as a file path and lose the connection it is read through.
        if let remote, remote.path == path {
          try store.addSource(
            remote: remote.connectionID.uuidString, bucket: remote.bucket, prefix: remote.prefix)
        } else {
          try store.addSource(kind: .night, path: path)
        }
        recorded += 1
      }
      // The profile kept for these sources, recorded with them; applied by nothing here.
      if let importing, let kept = importing.profileToRecord(for: request) {
        for path in request.paths {
          let kind: ProjectSource.Kind =
            importing.remoteTarget?.path == path ? .remoteNight : .night
          try store.setProfile(kept.id, kind: kind, path: path)
        }
      }
      // The sheet just read that prefix: its count is a measurement, so the stage shows it
      // instead of a bare row until the user rescans (a remote-only project adopts no plan,
      // `runRequest()` naming local nights alone).
      if let remote, let plan = importing?.plan, plan.inventory.root == remote.path {
        adoptRemoteScan(plan, of: remote)
      }
      imports.append(request)
      edited()
      // The sources first: whether the sheet's plan is the project's scan depends on them.
      refresh()
      adoptScan(of: importing, for: request)
      closeImport()
      refresh()
      if isNewNight && scan == nil {
        rescan()
        rescanAfterAdd = isScanning
      }
    } catch {
      // Some folders may be recorded: the last scan no longer describes the project.
      if recorded > 0 { edited() }
      dropScan()
      refresh()
      self.error = UserFacingError(error)
      importError = self.error
    }
  }
}
