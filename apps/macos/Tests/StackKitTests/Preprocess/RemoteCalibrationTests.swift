import Foundation
import ProjectKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0154, the calibration half: a bucket's raw frames are read only when a master has to be
/// built, the proofs that decide it cover their bytes, and what step 1 downloads is budgeted.
@Suite("Remote calibration — read only to build, proven by bytes")
struct RemoteCalibrationTests {
  typealias RemoteNight = RemoteLaneTests.RemoteNight

  /// The golden night with every calibration frame moved into a bucket, the lights left where
  /// they are, and the bucket holding them.
  struct RemoteCalibration {
    let inventory: Inventory
    let bucket: FrameStagerTests.FakeBucket
    let work: URL

    static func make() throws -> Self {
      let root = try InventoryBuilderFallbackTests.folder("cal")
      let inventory = try MasterBuilderTests.scan("golden-single-night", under: root)
      var objects: [String: Data] = [:]
      var sets: [FrameSet] = []
      for set in inventory.sets {
        guard set.key.type != .light else {
          sets.append(set)
          continue
        }
        var frames: [CaptureFrame] = []
        for frame in set.frames {
          let key = "cal/" + PathMeta.baseName(frame.path)
          objects[key] = try Data(contentsOf: URL(fileURLWithPath: frame.path))
          var moved = frame
          moved.path = "s3://astro/" + key
          frames.append(moved)
        }
        sets.append(FrameSet(key: set.key, frames: frames, indices: set.indices))
      }
      var remote = inventory
      remote.sets = sets
      return Self(
        inventory: remote, bucket: FrameStagerTests.FakeBucket(objects: objects),
        work: root.appendingPathComponent("work/run_C"))
    }

    /// A builder that reads this bucket and knows what it holds now — what
    /// `Preprocessor.readingBuckets` hands step 1 at the start of every run.
    func builder() async -> MasterBuilder {
      var builder = MasterBuilder(runner: PipelineSiril().runner)
      builder.stager = FrameStager(stores: [bucket.store])
      builder.identities = await builder.stager.identities(
        of: inventory.sets.flatMap { $0.frames.map(\.path) })
      return builder
    }

    /// The calibration frames' keys in the bucket.
    var keys: [String] {
      inventory.sets.filter { $0.key.type != .light }.flatMap {
        $0.frames.compactMap { ProjectSource.remoteParts(of: $0.path)?.key }
      }
    }
  }

  /// The first run's masters as the library, as `CalibrationLibrary.reindex` marks them: `reuse`
  /// only considers library masters.
  static func library(_ built: MasterBuilder.Result) -> [CalibrationMaster] {
    built.masters.map { master in
      var fromLibrary = master
      fromLibrary.fromLibrary = true
      return fromLibrary
    }
  }

  @Test(
    "testRemoteCalibrationDownloadedOnlyWhenBuilding: a library master is reused, not refetched",
    .scratchDirectory)
  func testRemoteCalibrationDownloadedOnlyWhenBuilding() async throws {
    let night = try RemoteCalibration.make()
    // First run: the raw frames have to be read, so they are downloaded.
    let built = try await night.builder().build(
      night.inventory, into: night.work.appendingPathComponent("masters"), work: night.work)
    #expect(!built.masters.isEmpty)
    let downloaded = night.bucket.downloaded.count
    #expect(downloaded > 0, "a master built from a bucket's frames reads them")

    // Second run, the bucket listed again as every run does before step 1.
    let reused = try await night.builder().build(
      night.inventory, into: night.work.appendingPathComponent("masters2"), work: night.work,
      library: Self.library(built))

    #expect(
      reused.warnings.filter { $0.contains("reused library master") }.count
        == built.masters.count, "the proof held for every master: \(reused.warnings)")
    #expect(
      night.bucket.downloaded.count == downloaded,
      "a reused master never fetches its frames again: \(night.bucket.downloaded.count)")
  }

  @Test(
    "testFrameUploadedAgainRebuildsItsMasterOnly: a new ETag under the same key is a new frame",
    .scratchDirectory)
  func testFrameUploadedAgainRebuildsItsMasterOnly() async throws {
    let night = try RemoteCalibration.make()
    let built = try await night.builder().build(
      night.inventory, into: night.work.appendingPathComponent("masters"), work: night.work)
    let downloaded = night.bucket.downloaded.count
    let changed = try #require(
      night.inventory.sets.first { $0.key.type != .light && !$0.frames.isEmpty })
    let key = try #require(ProjectSource.remoteParts(of: changed.frames[0].path)?.key)
    night.bucket.replace(key, with: Data("another exposure".utf8))

    let second = try await night.builder().build(
      night.inventory, into: night.work.appendingPathComponent("masters2"), work: night.work,
      library: Self.library(built))

    #expect(
      second.warnings.filter { $0.contains("rebuilding the") }.count == 1,
      "only the set holding the new upload is rebuilt: \(second.warnings)")
    #expect(
      second.warnings.filter { $0.contains("reused library master") }.count
        == built.masters.count - 1, "every other master still proves its frames")
    #expect(
      night.bucket.downloaded.count - downloaded == changed.frames.count,
      "and only its frames are downloaded again")
  }

  @Test(
    "testRemoteSigCarriesIdentities: a bucket-built master signs the bytes it read",
    .scratchDirectory)
  func testRemoteSigCarriesIdentities() async throws {
    let night = try RemoteCalibration.make()
    let builder = await night.builder()

    let built = try await builder.build(
      night.inventory, into: night.work.appendingPathComponent("masters"), work: night.work)

    let master = try #require(built.masters.first)
    let set = try #require(
      night.inventory.sets.first { $0.key.type != .light && master.satisfies($0.key) })
    let paths = set.frames.map(\.path)
    let recorded = try #require(PoolSignature.read(at: PoolSignature.sidecar(of: master.path)))
    #expect(
      recorded.hash == PoolSignature.of(paths, identities: builder.identities),
      "the .sig names each frame by what the bucket holds (size|etag)")
    #expect(
      recorded.hash != PoolSignature.of(paths),
      "never by its key alone: `s3://…|?` matches whatever is uploaded there next")
  }

  @Test("a run whose bucket has no connection is refused before Siril starts", .scratchDirectory)
  func testRunRefusesAnUnreadableBucket() async throws {
    let night = try await RemoteNight.make()
    var inventory = night.fixture.inventory
    inventory.sets = inventory.sets.map { set in
      set.key.type == .light && set.key.filter == "L" ? night.lights : set
    }
    let request = PreprocessRequest(
      inventory: inventory, output: night.fixture.out, work: night.fixture.work,
      runID: "R_no_conn", mode: .deepsky)
    // No store at all: the frames of the bucket cannot be read by this run.
    let preprocessor = Preprocessor(tools: .init(runner: PipelineSiril().runner))

    await #expect(throws: PreprocessError.self) {
      _ = try await preprocessor.perform(request) { _ in }
    }

    #expect(
      night.bucket.downloaded.isEmpty,
      "refused before a single frame was read — not a lane failing after the masters")
  }

  @Test(
    "an anchored lane whose night cannot be downloaded fails, it never stacks the rest",
    .scratchDirectory)
  func testAnchoredLaneFailsOnAStagingFailure() async throws {
    let night = try await RemoteNight.make()
    night.bucket.fail(true)
    var stacker = ChannelStacker(
      runner: PipelineSiril().runner, trailProbe: { _, _ in (false, 0.1) })
    stacker.stager = FrameStager(stores: [night.bucket.store])

    // The anchored path is the normal one — a one-night run is anchored too.
    let outcome = try await GroupedChannelStacker(
      stacker: stacker, parity: ParityCache(runner: PipelineSiril().runner),
      anchorNight: night.lights.key.session
    ).stack(
      [night.lights], filter: "L", inventory: night.fixture.inventory,
      masters: night.fixture.masters, work: night.fixture.work, out: night.fixture.out)

    #expect(outcome.masterPath == nil, "no master from the nights it could read")
    #expect(outcome.error != nil, "the lane carries the failure, not a « night skipped » warning")
  }

  @Test(
    "the defect map reads files: virtual paths read nothing, the staged copies read everything",
    .scratchDirectory)
  func testRemoteDarkKeepsItsDefectMap() throws {
    let root = try ScratchDirectory.url.appendingPathComponent("defects")
    // Eight mono darks, the floor `DarkDefects.scan` needs, with one hot pixel in every frame.
    var staged: [String] = []
    for index in 0..<8 {
      var pixels = [UInt16](repeating: 500, count: 16 * 16)
      pixels[42] = 60000
      let url = try TestFITS.write(
        String(format: "%05d_d_%d.fits", index + 1, index), in: root, width: 16, height: 16,
        planes: [pixels], cards: ["EXPTIME": "300.0"])
      staged.append(url.path)
    }

    // What the bug was: the original paths of a bucket's dark pool read nothing at all, so the
    // map was silently dropped — and an existing one deleted (R2).
    #expect(DarkDefects.scan(staged.map { "s3://astro/darks/" + PathMeta.baseName($0) }) == nil)
    let read = try #require(DarkDefects.scan(staged), "the staged copies are readable files")

    // What the pattern counts as is `DarkDefects`' own rule; that it read the frames at all is
    // this card's business.
    #expect(!read.summary.isEmpty, "the scan measured the staged frames: \(read.summary)")
  }

  @Test("a remote calibration frame's .sig covers its bytes, not just its key")
  func testRemotePoolSignatureCoversTheBytes() throws {
    let paths = ["s3://astro/darks/d_1.fits", "s3://astro/darks/d_2.fits"]

    let first = PoolSignature.of(paths, identities: [paths[0]: "100|e1", paths[1]: "100|e2"])
    let same = PoolSignature.of(paths, identities: [paths[0]: "100|e1", paths[1]: "100|e2"])
    let reuploaded = PoolSignature.of(paths, identities: [paths[0]: "100|e9", paths[1]: "100|e2"])
    let blind = PoolSignature.of(paths)

    #expect(first == same)
    #expect(first != reuploaded, "a frame re-uploaded under the same key rebuilds its master")
    #expect(blind != first, "and a signature taken without the bytes is not the same proof")
  }

  @Test(
    "the wrong-sensor guard still measures a light that lives in a bucket", .scratchDirectory)
  func testGuardMeasuresARemoteLight() throws {
    var light = CaptureFrame(path: "s3://astro/M31/l_1.fits")
    light.type = .light
    light.width = 6248
    light.height = 4176
    // A master of another sensor: a real file, so the guard can measure it.
    let root = try ScratchDirectory.url.appendingPathComponent("guard")
    try TestFITS.write("master_BIAS.fits", in: root, width: 16, height: 16, pixel: 100, cards: [:])
    let other = CalibrationMaster(
      type: .bias, path: root.appendingPathComponent("master_BIAS.fits").path)

    let kept = DimensionGuard.keepMatching(
      [other], lightPath: light.path, lightSize: (width: light.width, height: light.height))

    #expect(kept.masters.isEmpty, "another sensor's master leaves the pool")
    #expect(kept.note != nil, "and the run says so")
    #expect(
      DimensionGuard.keepMatching([other], lightPath: light.path).masters.count == 1,
      "without the scan's size nothing can be measured: the pool is left untouched")
  }

  @Test("the scratch estimate covers the calibration frames step 1 downloads")
  func testScratchEstimateCoversCalibrationDownloads() throws {
    var light = CaptureFrame(path: "/c/M31/l_1.fits")
    light.type = .light
    light.width = 100
    light.height = 100
    light.channels = 1
    var flat = CaptureFrame(path: "s3://astro/flats/f_1.fits")
    flat.type = .flat
    flat.width = 4000
    flat.height = 3000
    flat.channels = 1
    var inventory = Inventory(root: "/c/M31", frames: [light, flat])
    inventory.sets = [
      FrameSet(
        key: SetKey(type: .light, object: "M 31", filter: "L", exposureMs: 1000), frames: [light],
        indices: [0]),
      FrameSet(key: SetKey(type: .flat, filter: "L"), frames: [flat], indices: [1]),
    ]

    let estimate = try ScratchEstimate(inventory, settings: PreprocessSettings())

    #expect(
      estimate.bytes >= 4000 * 3000 * 2,
      "the flats downloaded in step 1 are budgeted: \(estimate.bytes) for \(estimate.lane)")
  }
}
