internal import Foundation

extension Preprocessor {
  /// What every lane of one run reads.
  struct LaneRun {
    var plan: NightPlan
    var request: PreprocessRequest
    var parity: ParityCache
    var emitter: RunEmitter
  }

  /// The outcome of `lane`: its record when a resume may reuse it, else the lane stacked (the
  /// calibration masters built on first need, into `pool`) and recorded.
  func laneOutcome(
    _ lane: String, of run: LaneRun, pool: inout [CalibrationMaster]?,
    journal: inout PreprocessJournal, result: inout PreprocessResult
  ) async throws -> ChannelOutcome {
    let (plan, request, emitter) = (run.plan, run.request, run.emitter)
    var rerun: String?
    if request.resuming {
      switch reusable(lane, plan: plan, request: request, emitter: emitter) {
      case .reused(let outcome): return outcome
      case .rerun(let reason): rerun = reason
      }
    }
    let masters: [CalibrationMaster]
    if let pool {
      masters = pool
    } else {
      masters = try await buildMasters(request, emitter: emitter, into: &result)
      pool = masters
    }
    let outcome = try await stackChannel(
      lane, plan: plan, request: request, pool: masters, parity: run.parity, emitter: emitter,
      note: rerun.map { "\(lane) re-runs: \($0)" })
    // Only a run that can pause or resumes leaves checkpoints: a run without a gate keeps the
    // output folder it always wrote.
    if request.pause != nil || request.resuming {
      record(outcome, lane: lane, plan: plan, request: request, journal: &journal)
    }
    return outcome
  }

  /// What a resume does with a lane: reuse its record, or stack it again for a reason.
  enum Reuse {
    case reused(ChannelOutcome)
    case rerun(String)
  }

  /// The recorded outcome of `lane` when its record still matches `request` (card 0097), else
  /// why the lane must run — journalled under the lane's own step once it begins.
  func reusable(_ lane: String, plan: NightPlan, request: PreprocessRequest, emitter: RunEmitter)
    -> Reuse
  {
    let record: LaneRecord
    do {
      record = try LaneRecord.read(lane: lane, from: request.output)
    } catch CocoaError.fileReadNoSuchFile {
      return .rerun("no record")
    } catch {
      return .rerun("its record is unreadable (\(error.localizedDescription))")
    }
    if let reason = record.staleReason(lane: lane, plan: plan, request: request) {
      return .rerun(reason)
    }
    let outcome = record.outcome(in: request.output)
    let master = outcome.masterPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    emitter.begin("reusing \(outcome.object) \(lane)")
    emitter.line("\(lane): reusing \(master ?? "its record") — same frames, same settings")
    return .reused(outcome)
  }

  /// Keeps `outcome` as the checkpoint of `lane`.
  ///
  /// A record that cannot be written only costs a resume its reuse of this lane, never the run.
  func record(
    _ outcome: ChannelOutcome, lane: String, plan: NightPlan, request: PreprocessRequest,
    journal: inout PreprocessJournal
  ) {
    do {
      try LaneRecord(outcome, lane: lane, plan: plan, request: request).write(to: request.output)
    } catch {
      journal.warn("\(lane): checkpoint not written — a resume stacks it again: \(error)")
    }
  }
}
