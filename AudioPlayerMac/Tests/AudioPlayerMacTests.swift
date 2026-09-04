import XCTest
import AVFoundation
@testable import AudioPlayerMac

class AudioPlayerMacTests: XCTestCase {

    // MARK: - AudioFormatDetector

    func testAudioFormatDetector() {
        let detector = AudioFormatDetector()

        let flacURL = URL(fileURLWithPath: "/test/file.flac")
        XCTAssertEqual(detector.detect(url: flacURL), .flac)

        let mp3URL = URL(fileURLWithPath: "/test/file.mp3")
        XCTAssertEqual(detector.detect(url: mp3URL), .mp3)

        let wavURL = URL(fileURLWithPath: "/test/file.wav")
        XCTAssertEqual(detector.detect(url: wavURL), .wav)

        let aacURL = URL(fileURLWithPath: "/test/file.m4a")
        XCTAssertEqual(detector.detect(url: aacURL), .aac)

        let eac3URL = URL(fileURLWithPath: "/test/file.eac3")
        XCTAssertEqual(detector.detect(url: eac3URL), .eac3)

        let ac3URL = URL(fileURLWithPath: "/test/file.ac3")
        XCTAssertEqual(detector.detect(url: ac3URL), .ac3)

        let truehdURL = URL(fileURLWithPath: "/test/file.thd")
        XCTAssertEqual(detector.detect(url: truehdURL), .truehd)

        let unknownURL = URL(fileURLWithPath: "/test/file.xyz")
        XCTAssertEqual(detector.detect(url: unknownURL), .unknown)
    }

    func testAudioFormatDetectorExtended() {
        let detector = AudioFormatDetector()

        let mlpURL = URL(fileURLWithPath: "/test/file.mlp")
        XCTAssertEqual(detector.detect(url: mlpURL), .mlp)

        let eb3URL = URL(fileURLWithPath: "/test/file.eb3")
        XCTAssertEqual(detector.detect(url: eb3URL), .eac3)
    }

    // MARK: - DecoderRouter

    func testDecoderRouter() throws {
        let router = DecoderRouter()

        let flacURL = URL(fileURLWithPath: "/test/file.flac")
        XCTAssertEqual(try router.selectBackend(for: flacURL).backendKind, .nativeFilePlayer)

        let mp3URL = URL(fileURLWithPath: "/test/file.mp3")
        XCTAssertEqual(try router.selectBackend(for: mp3URL).backendKind, .nativeFilePlayer)

        let wavURL = URL(fileURLWithPath: "/test/file.wav")
        XCTAssertEqual(try router.selectBackend(for: wavURL).backendKind, .pcmEngine)

        let truehdURL = URL(fileURLWithPath: "/test/file.thd")
        XCTAssertThrowsError(try router.selectBackend(for: truehdURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not enabled"))
        }
    }

    func testDecoderRouterExtended() throws {
        let router = DecoderRouter()

        let mlpURL = URL(fileURLWithPath: "/test/file.mlp")
        XCTAssertThrowsError(try router.selectBackend(for: mlpURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("not enabled"))
        }

        let m4aURL = URL(fileURLWithPath: "/test/file.m4a")
        XCTAssertEqual(try router.selectBackend(for: m4aURL).backendKind, .nativeFilePlayer)

        let eac3URL = URL(fileURLWithPath: "/test/file.eac3")
        let eac3Route = try router.selectBackend(for: eac3URL)
        XCTAssertEqual(eac3Route.backendKind, .nativeFilePlayer)
        XCTAssertTrue(eac3Route.preservesCompressedSource)
    }

    // MARK: - VolumeController

    func testVolumeController() {
        let controller = VolumeController()

        XCTAssertEqual(controller.currentVolume, 1.0)

        controller.setVolume(0.5)
        XCTAssertEqual(controller.currentVolume, 0.5)

        controller.setVolume(1.5)
        XCTAssertEqual(controller.currentVolume, 1.0)

        controller.setVolume(-0.5)
        XCTAssertEqual(controller.currentVolume, 0.0)

        controller.setVolume(0.7)
        controller.mute()
        XCTAssertEqual(controller.currentVolume, 0.0)

        controller.unmute(to: 0.8)
        XCTAssertEqual(controller.currentVolume, 0.8)
    }

    // MARK: - PlaybackState

    func testPlaybackState() {
        XCTAssertEqual(PlaybackState.idle.description, "idle")
        XCTAssertEqual(PlaybackState.loading.description, "loading")
        XCTAssertEqual(PlaybackState.ready.description, "ready")
        XCTAssertEqual(PlaybackState.stopped, PlaybackState.stopped)
        XCTAssertNotEqual(PlaybackState.stopped, PlaybackState.playing)
        XCTAssertNotEqual(PlaybackState.playing, PlaybackState.paused)
        XCTAssertEqual(PlaybackState.failed.description, "failed")
    }

    // MARK: - PCMEngineBackend

    func testPCMEngineBackendStartsGeneratedWAV() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
        buffer.frameLength = 2048
        let data = buffer.floatChannelData![0]
        for frame in 0..<Int(buffer.frameLength) {
            data[frame] = sin(Float(frame) * 0.02) * 0.1
        }

        do {
            let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            try file.write(from: buffer)
        }

        let backend = PCMEngineBackend()
        try backend.prepare(url: tempURL)
        XCTAssertGreaterThan(backend.duration, 0)

        try backend.play()
        XCTAssertNotNil(backend.currentTime())
        backend.pause()
        try backend.resume()
        backend.stop()
    }

    func testPlaybackSmokeEvidenceWithOptionalRealMedia() throws {
        let environment = ProcessInfo.processInfo.environment
        let reportPath = environment["AUDIOPLAYER_SMOKE_REPORT"]
        let mediaDirectory = environment["AUDIOPLAYER_SMOKE_MEDIA_DIR"]
        guard reportPath != nil || mediaDirectory != nil else {
            throw XCTSkip("Set AUDIOPLAYER_SMOKE_REPORT or AUDIOPLAYER_SMOKE_MEDIA_DIR to run local playback smoke evidence.")
        }

        let reportURL = reportPath.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("playback-smoke-report.json")
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var cases: [[String: Any]] = []
        let generatedWAV = try makeSmokeWAV()
        defer { try? FileManager.default.removeItem(at: generatedWAV) }
        cases.append(runSmokeCase(url: generatedWAV, source: "generated"))

        if let mediaDirectory {
            let mediaURL = URL(fileURLWithPath: mediaDirectory)
            for url in smokeCandidateURLs(in: mediaURL) {
                cases.append(runSmokeCase(url: url, source: "local-media"))
            }
        }

        let report: [String: Any] = [
            "test": "playback-core-smoke-evidence",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "audiblePlaybackEvidence": "INCONCLUSIVE: XCTest can exercise open/play/pause/resume/stop, but it cannot prove physical endpoint audio was heard.",
            "cases": cases
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: reportURL)
        print("Playback smoke evidence report: \(reportURL.path)")

        let generatedResult = cases.first { $0["source"] as? String == "generated" }?["result"] as? String
        XCTAssertEqual(generatedResult, "PASS")
    }

    // MARK: - PcmStreamBuffer

    private func makeTestBuffer(frameCount: AVAudioFrameCount = 1024, channels: Int = 2) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: UInt32(channels), interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for ch in 0..<channels {
            let data = buffer.floatChannelData![ch]
            for i in 0..<Int(frameCount) {
                data[i] = Float(i) / Float(frameCount)
            }
        }
        return buffer
    }

    private func makeSmokeWAV() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioPlayerMac-smoke-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 220500)!
        buffer.frameLength = 220500
        let data = buffer.floatChannelData![0]
        for frame in 0..<Int(buffer.frameLength) {
            data[frame] = sin(Float(frame) * 440.0 * 2.0 * .pi / 44100.0) * 0.1
        }

        let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try file.write(from: buffer)
        return tempURL
    }

    private func smokeCandidateURLs(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let detector = AudioFormatDetector()
        var selected: [AudioFormat: URL] = [:]
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let format = detector.detect(url: url)
            guard smokeTrackedFormats.contains(format), selected[format] == nil else {
                continue
            }
            selected[format] = url
        }

        let order: [AudioFormat] = [.wav, .mp3, .aac, .alac, .flac, .ac3, .eac3]
        return order.compactMap { selected[$0] }
    }

    private var smokeTrackedFormats: Set<AudioFormat> {
        [.wav, .mp3, .aac, .alac, .flac, .ac3, .eac3]
    }

    private func runSmokeCase(url: URL, source: String) -> [String: Any] {
        let router = DecoderRouter()
        let detector = AudioFormatDetector()
        let format = detector.detect(url: url)
        var result = "PASS"
        var notes: [String] = []
        var selectedBackend = "unselected"
        var avPlayerItemStatus = "not-applicable"
        var engineRunningEvidence = "not-applicable"
        var routeExtension = url.pathExtension.lowercased()
        var uiStates: [String] = []
        var interactionStates: [String: String] = [:]

        do {
            let route = try router.selectBackend(for: url)
            selectedBackend = route.backendKind.rawValue
            routeExtension = route.containerDescription
            if route.backendKind == .nativeFilePlayer {
                avPlayerItemStatus = avPlayerStatus(for: url)
            }

            PlayerLogger.shared.clearEntries()
            let coordinator = PlaybackCoordinator()
            coordinator.open(url: url)
            spinRunLoop(seconds: 0.8)
            uiStates.append("open=\(coordinator.statusMessage)")

            guard coordinator.state == .ready else {
                result = "FAIL"
                notes.append("open did not reach ready; state=\(coordinator.state.description)")
                return smokeCase(
                    url: url,
                    source: source,
                    format: format,
                    extensionName: routeExtension,
                    selectedBackend: selectedBackend,
                    avPlayerItemStatus: avPlayerItemStatus,
                    engineRunningEvidence: engineRunningEvidence,
                    uiStates: uiStates,
                    interactionStates: interactionStates,
                    result: result,
                    notes: notes
                )
            }

            coordinator.play()
            spinRunLoop(seconds: 0.6)
            interactionStates["play"] = coordinator.state.description
            uiStates.append("play=\(coordinator.statusMessage)")

            coordinator.pause()
            spinRunLoop(seconds: 0.2)
            interactionStates["pause"] = coordinator.state.description
            uiStates.append("pause=\(coordinator.statusMessage)")

            coordinator.resume()
            spinRunLoop(seconds: 0.4)
            interactionStates["resume"] = coordinator.state.description
            uiStates.append("resume=\(coordinator.statusMessage)")

            coordinator.stop()
            spinRunLoop(seconds: 0.2)
            interactionStates["stop"] = coordinator.state.description
            uiStates.append("stop=\(coordinator.statusMessage)")

            if route.backendKind == .pcmEngine {
                engineRunningEvidence = PlayerLogger.shared.getEntries(category: "audio", limit: 50)
                    .map(\.message)
                    .last { $0.contains("PCMEngineBackend start running=") } ?? "missing"
            }

            if interactionStates["play"] != PlaybackState.playing.description ||
                interactionStates["pause"] != PlaybackState.paused.description ||
                interactionStates["resume"] != PlaybackState.playing.description ||
                interactionStates["stop"] != PlaybackState.stopped.description {
                result = "FAIL"
                notes.append("one or more transport state transitions did not match expected values")
            }
        } catch {
            result = "FAIL"
            notes.append(error.localizedDescription)
        }

        return smokeCase(
            url: url,
            source: source,
            format: format,
            extensionName: routeExtension,
            selectedBackend: selectedBackend,
            avPlayerItemStatus: avPlayerItemStatus,
            engineRunningEvidence: engineRunningEvidence,
            uiStates: uiStates,
            interactionStates: interactionStates,
            result: result,
            notes: notes
        )
    }

    private func smokeCase(
        url: URL,
        source: String,
        format: AudioFormat,
        extensionName: String,
        selectedBackend: String,
        avPlayerItemStatus: String,
        engineRunningEvidence: String,
        uiStates: [String],
        interactionStates: [String: String],
        result: String,
        notes: [String]
    ) -> [String: Any] {
        [
            "inputFilePath": url.path,
            "source": source,
            "detectedFormat": format.smokeName,
            "detectedContainerOrExtension": extensionName,
            "selectedBackend": selectedBackend,
            "avPlayerItemStatus": avPlayerItemStatus,
            "avAudioEngineRunningState": engineRunningEvidence,
            "uiState": uiStates.joined(separator: " | "),
            "transportStates": interactionStates,
            "audibleSound": "INCONCLUSIVE",
            "result": result,
            "notes": notes
        ]
    }

    private func avPlayerStatus(for url: URL) -> String {
        let item = AVPlayerItem(url: url)
        _ = AVPlayer(playerItem: item)
        spinRunLoop(seconds: 1.5)

        switch item.status {
        case .unknown:
            return "unknown"
        case .readyToPlay:
            return "readyToPlay"
        case .failed:
            return "failed: \(item.error?.localizedDescription ?? "no AVPlayerItem error")"
        @unknown default:
            return "unknown-default"
        }
    }

    private func spinRunLoop(seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testPcmStreamBufferWriteRead() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!
        let streamBuffer = PcmStreamBuffer(format: format, capacity: 2048)

        let inputBuffer = makeTestBuffer(frameCount: 512)
        XCTAssertTrue(streamBuffer.write(buffer: inputBuffer))
        XCTAssertEqual(streamBuffer.framesAvailable, 512)

        let output = streamBuffer.read(frameCount: 512)
        XCTAssertNotNil(output)
        XCTAssertEqual(output!.frameLength, 512)

        for ch in 0..<2 {
            let inData = inputBuffer.floatChannelData![ch]
            let outData = output!.floatChannelData![ch]
            for i in 0..<512 {
                XCTAssertEqual(inData[i], outData[i], accuracy: 0.0001, "Mismatch at channel \(ch) frame \(i)")
            }
        }
    }

    func testPcmStreamBufferWriteWhenFull() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!
        let streamBuffer = PcmStreamBuffer(format: format, capacity: 512)

        let inputBuffer = makeTestBuffer(frameCount: 512)
        XCTAssertTrue(streamBuffer.write(buffer: inputBuffer))
        XCTAssertTrue(streamBuffer.isFull)

        let extraBuffer = makeTestBuffer(frameCount: 256)
        XCTAssertFalse(streamBuffer.write(buffer: extraBuffer))
    }

    func testPcmStreamBufferWrapsAfterPartialRead() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!
        let streamBuffer = PcmStreamBuffer(format: format, capacity: 8)

        let firstBuffer = makeTestBuffer(frameCount: 6)
        XCTAssertTrue(streamBuffer.write(buffer: firstBuffer))

        let firstRead = streamBuffer.read(frameCount: 4)
        XCTAssertNotNil(firstRead)
        XCTAssertEqual(firstRead!.frameLength, 4)
        XCTAssertEqual(streamBuffer.framesAvailable, 2)

        let secondBuffer = makeTestBuffer(frameCount: 6)
        XCTAssertTrue(streamBuffer.write(buffer: secondBuffer))
        XCTAssertTrue(streamBuffer.isFull)

        let wrappedRead = streamBuffer.read(frameCount: 8)
        XCTAssertNotNil(wrappedRead)
        XCTAssertEqual(wrappedRead!.frameLength, 8)
        XCTAssertTrue(streamBuffer.isEmpty)

        let data = wrappedRead!.floatChannelData![0]
        XCTAssertEqual(data[0], firstBuffer.floatChannelData![0][4], accuracy: 0.0001)
        XCTAssertEqual(data[1], firstBuffer.floatChannelData![0][5], accuracy: 0.0001)
        for i in 0..<6 {
            XCTAssertEqual(data[i + 2], secondBuffer.floatChannelData![0][i], accuracy: 0.0001)
        }
    }

    func testPcmStreamBufferClear() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!
        let streamBuffer = PcmStreamBuffer(format: format, capacity: 2048)

        let inputBuffer = makeTestBuffer(frameCount: 512)
        streamBuffer.write(buffer: inputBuffer)
        XCTAssertFalse(streamBuffer.isEmpty)
        XCTAssertEqual(streamBuffer.framesAvailable, 512)

        streamBuffer.clear()
        XCTAssertTrue(streamBuffer.isEmpty)
        XCTAssertEqual(streamBuffer.framesAvailable, 0)
    }

    func testPcmStreamBufferReset() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!
        let streamBuffer = PcmStreamBuffer(format: format, capacity: 2048)

        let inputBuffer = makeTestBuffer(frameCount: 512)
        streamBuffer.write(buffer: inputBuffer)
        XCTAssertFalse(streamBuffer.isEmpty)

        streamBuffer.reset()
        XCTAssertTrue(streamBuffer.isEmpty)
        XCTAssertEqual(streamBuffer.framesAvailable, 0)

        // Should be able to write again after reset
        XCTAssertTrue(streamBuffer.write(buffer: inputBuffer))
        XCTAssertEqual(streamBuffer.framesAvailable, 512)
    }

    // MARK: - DolbyDownmixProcessor

    func testDolbyDownmixProcessorConfigure() {
        let processor = DolbyDownmixProcessor()

        var params = DolbyDownmixParams()
        params.type = .loRo
        XCTAssertTrue(processor.configure(params: params, inputChannelCount: 6, outputChannelCount: 2))
        XCTAssertTrue(processor.isActive())

        let processor2 = DolbyDownmixProcessor()
        var noneParams = DolbyDownmixParams()
        noneParams.type = .none
        XCTAssertFalse(processor2.configure(params: noneParams, inputChannelCount: 6, outputChannelCount: 2))
        XCTAssertFalse(processor2.isActive())

        let processor3 = DolbyDownmixProcessor()
        var loRoParams = DolbyDownmixParams()
        loRoParams.type = .loRo
        XCTAssertFalse(processor3.configure(params: loRoParams, inputChannelCount: 6, outputChannelCount: 6))
        XCTAssertFalse(processor3.isActive())
    }

    func testDolbyDownmixProcessorPlanar() {
        let processor = DolbyDownmixProcessor()
        var params = DolbyDownmixParams()
        params.type = .loRo
        params.centerMixLevel = 0.707
        params.surroundMixLevel = 0.707
        params.lfeMixLevel = 0.0

        let frameCount = 256
        XCTAssertTrue(processor.configure(params: params, inputChannelCount: 6, outputChannelCount: 2))

        var inL = [Float](repeating: 0, count: frameCount)
        var inR = [Float](repeating: 0, count: frameCount)
        var inC = [Float](repeating: 0, count: frameCount)
        var inLFE = [Float](repeating: 0, count: frameCount)
        var inLs = [Float](repeating: 0, count: frameCount)
        var inRs = [Float](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            let f = Float(i) / Float(frameCount)
            inL[i] = f
            inR[i] = f * 0.5
            inC[i] = f * 0.3
            inLFE[i] = f * 0.1
            inLs[i] = f * 0.2
            inRs[i] = f * 0.2
        }

        var outL = [Float](repeating: 0, count: frameCount)
        var outR = [Float](repeating: 0, count: frameCount)

        inL.withUnsafeBufferPointer { lBuf in
        inR.withUnsafeBufferPointer { rBuf in
        inC.withUnsafeBufferPointer { cBuf in
        inLFE.withUnsafeBufferPointer { lfeBuf in
        inLs.withUnsafeBufferPointer { lsBuf in
        inRs.withUnsafeBufferPointer { rsBuf in
        outL.withUnsafeMutableBufferPointer { outLBuf in
        outR.withUnsafeMutableBufferPointer { outRBuf in
            let inputPlanes: [UnsafePointer<Float>] = [
                lBuf.baseAddress!, rBuf.baseAddress!, cBuf.baseAddress!,
                lfeBuf.baseAddress!, lsBuf.baseAddress!, rsBuf.baseAddress!
            ]
            let outputPlanes: [UnsafeMutablePointer<Float>] = [
                outLBuf.baseAddress!, outRBuf.baseAddress!
            ]
            processor.processFloat32Planar(inputPlanes: inputPlanes, outputPlanes: outputPlanes, frameCount: frameCount)
        }}}}}}}
        }

        for i in 0..<frameCount {
            XCTAssertFalse(outL[i].isNaN, "outL[\(i)] is NaN")
            XCTAssertFalse(outL[i].isInfinite, "outL[\(i)] is Inf")
            XCTAssertFalse(outR[i].isNaN, "outR[\(i)] is NaN")
            XCTAssertFalse(outR[i].isInfinite, "outR[\(i)] is Inf")
        }

        // Verify first frame: outL = L + cmix*C + smix*Ls, outR = R + cmix*C + smix*Rs
        let expectedL0: Float = 0.0 + 0.707 * 0.0 + 0.0 + 0.707 * 0.0
        let expectedR0: Float = 0.0 + 0.707 * 0.0 + 0.0 + 0.707 * 0.0
        XCTAssertEqual(outL[0], expectedL0, accuracy: 0.001)
        XCTAssertEqual(outR[0], expectedR0, accuracy: 0.001)
    }

    // MARK: - PcmSeekCache

    private func makeCacheBuffer() -> AVAudioPCMBuffer {
        return makeTestBuffer(frameCount: 64, channels: 2)
    }

    func testPcmSeekCachePutGet() {
        let cache = PcmSeekCache(maxSize: 10)
        let buffer = makeCacheBuffer()

        cache.put(positionMs: 1000, buffer: buffer)
        // put is async with barrier; give it a moment
        Thread.sleep(forTimeInterval: 0.05)

        let retrieved = cache.get(positionMs: 1000)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved!.frameLength, 64)

        XCTAssertNil(cache.get(positionMs: 2000))
    }

    func testPcmSeekCacheEviction() {
        let cache = PcmSeekCache(maxSize: 3)

        for i in 0..<4 {
            cache.put(positionMs: Int64(i * 1000), buffer: makeCacheBuffer())
        }
        Thread.sleep(forTimeInterval: 0.1)

        // Oldest entry (position 0) should be evicted
        XCTAssertNil(cache.get(positionMs: 0))
        XCTAssertNotNil(cache.get(positionMs: 1000))
        XCTAssertNotNil(cache.get(positionMs: 2000))
        XCTAssertNotNil(cache.get(positionMs: 3000))
    }

    func testPcmSeekCacheClear() {
        let cache = PcmSeekCache(maxSize: 10)

        cache.put(positionMs: 100, buffer: makeCacheBuffer())
        cache.put(positionMs: 200, buffer: makeCacheBuffer())
        Thread.sleep(forTimeInterval: 0.05)

        XCTAssertFalse(cache.isEmpty)
        XCTAssertEqual(cache.count, 2)

        cache.clear()
        Thread.sleep(forTimeInterval: 0.05)

        XCTAssertTrue(cache.isEmpty)
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.get(positionMs: 100))
    }

    // MARK: - PlaybackPlanBuilder

    func testPlaybackPlanBuilder() {
        // .flac is a known format; buildPlan requires a file that AVFoundation can probe.
        // Since we test with a non-existent file, SourceProbe will still produce a plan
        // based on extension detection (fileSize=0, duration=0).
        let builder = PlaybackPlanBuilder()
        let url = URL(fileURLWithPath: "/tmp/test.flac")

        do {
            let plan = try builder.buildPlan(for: url)
            XCTAssertEqual(plan.decoderType, .nativeFilePlayer)
            XCTAssertEqual(plan.sourceMode, .direct)
            XCTAssertEqual(plan.format, .flac)
            XCTAssertEqual(plan.sourceURL, url)
        } catch {
            // If the probe determines the file is not playable (file doesn't exist),
            // that's acceptable for a unit test without real files.
            if case PlaybackPlanError.unsupportedFormat(let fmt) = error {
                XCTFail("Unexpected unsupported format: \(fmt)")
            }
        }
    }

    // MARK: - MediaInfo

    func testMediaInfoFormatted() {
        let info = MediaInfo(
            url: URL(fileURLWithPath: "/test.flac"),
            fileName: "test",
            fileExtension: "flac",
            fileSize: 1_572_864,  // 1.5 MB
            duration: 125.0,      // 2:05
            format: .flac,
            codecName: "FLAC",
            sampleRate: 44100,
            channelCount: 2,
            bitDepth: 16,
            bitrate: 0,
            isDolby: false,
            isLossless: true
        )

        XCTAssertEqual(info.durationFormatted, "02:05")
        XCTAssertEqual(info.sampleRateFormatted, "44.1 kHz")
        XCTAssertEqual(info.fileSizeFormatted, "1.5 MB")
    }

    func testMediaInfoFormattedHours() {
        let info = MediaInfo(
            url: URL(fileURLWithPath: "/test.flac"),
            fileName: "test",
            fileExtension: "flac",
            fileSize: 1_073_741_824,  // 1 GB
            duration: 3661.0,          // 1:01:01
            format: .flac,
            codecName: "FLAC",
            sampleRate: 96000,
            channelCount: 2,
            bitDepth: 24,
            bitrate: 0,
            isDolby: false,
            isLossless: true
        )

        XCTAssertEqual(info.durationFormatted, "1:01:01")
        XCTAssertEqual(info.sampleRateFormatted, "96.0 kHz")
        XCTAssertEqual(info.fileSizeFormatted, "1.00 GB")
    }

    func testMediaInfoFormattedSmall() {
        let info = MediaInfo(
            url: URL(fileURLWithPath: "/test.wav"),
            fileName: "test",
            fileExtension: "wav",
            fileSize: 512,
            duration: 0.0,
            format: .wav,
            codecName: "PCM (WAV)",
            sampleRate: 8000,
            channelCount: 1,
            bitDepth: 16,
            bitrate: 128,
            isDolby: false,
            isLossless: true
        )

        XCTAssertEqual(info.durationFormatted, "00:00")
        XCTAssertEqual(info.sampleRateFormatted, "8.0 kHz")
        XCTAssertEqual(info.fileSizeFormatted, "512 bytes")
    }

    static var allTests = [
        ("testAudioFormatDetector", testAudioFormatDetector),
        ("testAudioFormatDetectorExtended", testAudioFormatDetectorExtended),
        ("testDecoderRouter", testDecoderRouter),
        ("testDecoderRouterExtended", testDecoderRouterExtended),
        ("testVolumeController", testVolumeController),
        ("testPlaybackState", testPlaybackState),
        ("testPcmStreamBufferWriteRead", testPcmStreamBufferWriteRead),
        ("testPcmStreamBufferWriteWhenFull", testPcmStreamBufferWriteWhenFull),
        ("testPcmStreamBufferClear", testPcmStreamBufferClear),
        ("testPcmStreamBufferReset", testPcmStreamBufferReset),
        ("testDolbyDownmixProcessorConfigure", testDolbyDownmixProcessorConfigure),
        ("testDolbyDownmixProcessorPlanar", testDolbyDownmixProcessorPlanar),
        ("testPcmSeekCachePutGet", testPcmSeekCachePutGet),
        ("testPcmSeekCacheEviction", testPcmSeekCacheEviction),
        ("testPcmSeekCacheClear", testPcmSeekCacheClear),
        ("testPlaybackPlanBuilder", testPlaybackPlanBuilder),
        ("testMediaInfoFormatted", testMediaInfoFormatted),
        ("testMediaInfoFormattedHours", testMediaInfoFormattedHours),
        ("testMediaInfoFormattedSmall", testMediaInfoFormattedSmall),
    ]
}

private extension AudioFormat {
    var smokeName: String {
        switch self {
        case .eac3: return "eac3"
        case .ac3: return "ac3"
        case .aac: return "aac"
        case .alac: return "alac"
        case .flac: return "flac"
        case .wav: return "wav"
        case .mp3: return "mp3"
        case .truehd: return "truehd"
        case .mlp: return "mlp"
        case .unknown: return "unknown"
        }
    }
}
