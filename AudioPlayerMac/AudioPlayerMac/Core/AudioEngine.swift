import AVFoundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var scheduledFile: AVAudioFile?
    private var scheduledFileStartFrame: AVAudioFramePosition = 0
    private var scheduledCompletion: (() -> Void)?

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
    }

    var isRunning: Bool {
        engine.isRunning
    }

    func preparePCMFile(url: URL) throws -> (duration: TimeInterval, formatDescription: String) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0
        let description = "\(format.sampleRate)Hz \(format.channelCount)ch interleaved=\(format.isInterleaved)"
        return (duration, description)
    }

    func playPCMFile(url: URL, startTime: TimeInterval, completion: (() -> Void)? = nil) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let startFrame = max(
            AVAudioFramePosition(0),
            min(AVAudioFramePosition(startTime * format.sampleRate), file.length)
        )
        let remainingFrames = max(AVAudioFramePosition(0), file.length - startFrame)

        playerNode.stop()
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()

        scheduledFile = file
        scheduledFileStartFrame = startFrame
        scheduledCompletion = completion

        guard remainingFrames > 0 else {
            completion?()
            return
        }

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.scheduledCompletion?()
            }
        }

        if !engine.isRunning {
            try engine.start()
        }

        playerNode.play()

        PlayerLogger.shared.info(
            category: "audio",
            message: "AVAudioEngine running=\(engine.isRunning) scheduled PCM file: \(format.sampleRate)Hz \(format.channelCount)ch startFrame=\(startFrame) remainingFrames=\(remainingFrames)"
        )
    }

    func pause() {
        playerNode.pause()
        PlayerLogger.shared.info(category: "audio", message: "AVAudioEngine pause requested running=\(engine.isRunning)")
    }

    func resume() {
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
        PlayerLogger.shared.info(category: "audio", message: "AVAudioEngine resume requested running=\(engine.isRunning)")
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        scheduledFile = nil
        scheduledFileStartFrame = 0
        scheduledCompletion = nil
        PlayerLogger.shared.info(category: "audio", message: "AVAudioEngine stopped running=\(engine.isRunning)")
    }

    func currentScheduledFileTime() -> TimeInterval? {
        guard let file = scheduledFile,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }

        let frame = scheduledFileStartFrame + AVAudioFramePosition(playerTime.sampleTime)
        return Double(frame) / file.processingFormat.sampleRate
    }

    func setVolume(_ volume: Float) {
        playerNode.volume = volume
        engine.mainMixerNode.outputVolume = volume
    }

    /// Snapshot the current output format.  Requires the engine to be running
    /// and a file to be scheduled so that the output node format is populated.
    func currentOutputFormat(deviceName: String, hardwareBitDepth: Int?, hardwareIsFloat: Bool) -> OutputFormatInfo? {
        let format = engine.outputNode.outputFormat(forBus: 0)
        let asbd = format.streamDescription.pointee
        let bits = hardwareBitDepth ?? Int(asbd.mBitsPerChannel)
        return OutputFormatInfo(
            sampleRate: asbd.mSampleRate,
            channelCount: Int(asbd.mChannelsPerFrame),
            bitDepth: bits > 0 ? bits : 32,
            isFloat: hardwareIsFloat,
            deviceName: deviceName
        )
    }
}

/// Describes the actual output audio format reported by AVAudioEngine and
/// the CoreAudio HAL device.  Populated after the engine is started.
struct OutputFormatInfo {
    let sampleRate: Double
    let channelCount: Int
    let bitDepth: Int
    let isFloat: Bool
    let deviceName: String

    var bitDepthFormatted: String {
        if isFloat { return "\(bitDepth)-bit float" }
        return "\(bitDepth)-bit int"
    }

    var sampleRateFormatted: String {
        if sampleRate >= 1000 {
            return String(format: "%.1f kHz", sampleRate / 1000)
        }
        return String(format: "%.0f Hz", sampleRate)
    }
}
