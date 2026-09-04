import Foundation
import AVFoundation
import Combine

enum PlaybackState: Equatable, CustomStringConvertible {
    case idle
    case loading
    case ready
    case playing
    case paused
    case stopped
    case failed

    var description: String {
        switch self {
        case .idle: return "idle"
        case .loading: return "loading"
        case .ready: return "ready"
        case .playing: return "playing"
        case .paused: return "paused"
        case .stopped: return "stopped"
        case .failed: return "failed"
        }
    }
}

protocol PlaybackBackend: AnyObject {
    var name: String { get }
    var duration: TimeInterval { get }
    var seekRequiresRestart: Bool { get }
    var onFinished: (() -> Void)? { get set }
    var onFailed: ((Error) -> Void)? { get set }

    func prepare(url: URL) throws
    func play() throws
    func pause()
    func resume() throws
    func stop()
    func seek(to time: TimeInterval) throws
    func currentTime() -> TimeInterval?
    func setVolume(_ volume: Float)
    func currentOutputFormat(deviceName: String, hardwareBitDepth: Int?, hardwareIsFloat: Bool) -> OutputFormatInfo?
}

final class NativeFilePlayerBackend: PlaybackBackend {
    let name = PlaybackBackendKind.nativeFilePlayer.rawValue
    let seekRequiresRestart = false
    private let logger = PlayerLogger.shared
    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: Any?
    private(set) var duration: TimeInterval = 0

    var onFinished: (() -> Void)?
    var onFailed: ((Error) -> Void)?

    func prepare(url: URL) throws {
        stop()

        let item = AVPlayerItem(url: url)
        self.item = item
        player = AVPlayer(playerItem: item)

        let seconds = CMTimeGetSeconds(item.asset.duration)
        duration = seconds.isFinite && seconds > 0 ? seconds : 0

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.logItemStatus(item)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info(category: "player", message: "AVPlayer item reached end")
            self?.onFinished?()
        }

        logger.info(category: "player", message: "NativeFilePlayerBackend prepared duration=\(duration)s")
    }

    func play() throws {
        guard let player else {
            throw PlaybackError.backendNotPrepared(name)
        }
        player.play()
        logger.info(category: "player", message: "AVPlayer play requested rate=\(player.rate)")
    }

    func pause() {
        player?.pause()
        logger.info(category: "player", message: "AVPlayer pause requested rate=\(player?.rate ?? 0)")
    }

    func resume() throws {
        try play()
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation = nil
        item = nil
        player = nil
        duration = 0
        logger.info(category: "player", message: "AVPlayer stopped")
    }

    func seek(to time: TimeInterval) throws {
        guard let player else {
            throw PlaybackError.backendNotPrepared(name)
        }
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        // Default tolerances for fast seeking; AVPlayer handles seek-while-playing.
        player.seek(to: cmTime)
        logger.info(category: "player", message: "AVPlayer seek to \(time)s")
    }

    func currentTime() -> TimeInterval? {
        guard let player else { return nil }
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? seconds : nil
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    func currentOutputFormat(deviceName: String, hardwareBitDepth: Int?, hardwareIsFloat: Bool) -> OutputFormatInfo? {
        return nil
    }

    private func logItemStatus(_ item: AVPlayerItem) {
        switch item.status {
        case .unknown:
            logger.info(category: "player", message: "AVPlayer item status=unknown")
        case .readyToPlay:
            let seconds = CMTimeGetSeconds(item.duration)
            if seconds.isFinite && seconds > 0 {
                duration = seconds
            }
            logger.info(category: "player", message: "AVPlayer item status=readyToPlay duration=\(duration)s")
        case .failed:
            let error = item.error ?? PlaybackError.unsupported("AVPlayer item failed without an error")
            logger.error(category: "player", message: "AVPlayer item status=failed error=\(error.localizedDescription)")
            onFailed?(error)
        @unknown default:
            logger.warning(category: "player", message: "AVPlayer item status=unknown-default")
        }
    }
}

final class PCMEngineBackend: PlaybackBackend {
    let name = PlaybackBackendKind.pcmEngine.rawValue
    let seekRequiresRestart = true
    private let logger = PlayerLogger.shared
    private let audioEngine = AudioEngine()
    private var url: URL?
    private var restartTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var onFinished: (() -> Void)?
    var onFailed: ((Error) -> Void)?

    func prepare(url: URL) throws {
        stop()
        self.url = url
        restartTime = 0
        let info = try audioEngine.preparePCMFile(url: url)
        duration = info.duration
        logger.info(category: "audio", message: "PCMEngineBackend prepared format=\(info.formatDescription) duration=\(duration)s")
    }

    func play() throws {
        guard let url else {
            throw PlaybackError.backendNotPrepared(name)
        }
        try audioEngine.playPCMFile(url: url, startTime: restartTime) { [weak self] in
            self?.logger.info(category: "audio", message: "PCMEngineBackend reached end")
            self?.onFinished?()
        }
        logger.info(category: "audio", message: "PCMEngineBackend start running=\(audioEngine.isRunning)")
    }

    func pause() {
        restartTime = currentTime() ?? restartTime
        audioEngine.pause()
        logger.info(category: "audio", message: "PCMEngineBackend paused running=\(audioEngine.isRunning) time=\(restartTime)s")
    }

    func resume() throws {
        audioEngine.resume()
        logger.info(category: "audio", message: "PCMEngineBackend resumed running=\(audioEngine.isRunning)")
    }

    func stop() {
        audioEngine.stop()
        restartTime = 0
        logger.info(category: "audio", message: "PCMEngineBackend stopped running=\(audioEngine.isRunning)")
    }

    func seek(to time: TimeInterval) throws {
        restartTime = max(0, min(time, duration > 0 ? duration : time))
        logger.info(category: "audio", message: "PCMEngineBackend seek staged time=\(restartTime)s")
    }

    func currentTime() -> TimeInterval? {
        audioEngine.currentScheduledFileTime() ?? restartTime
    }

    func setVolume(_ volume: Float) {
        audioEngine.setVolume(volume)
    }

    func currentOutputFormat(deviceName: String, hardwareBitDepth: Int?, hardwareIsFloat: Bool) -> OutputFormatInfo? {
        return audioEngine.currentOutputFormat(deviceName: deviceName, hardwareBitDepth: hardwareBitDepth, hardwareIsFloat: hardwareIsFloat)
    }
}

enum PlaybackError: LocalizedError {
    case backendNotPrepared(String)
    case noFileLoaded
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .backendNotPrepared(let backend):
            return "\(backend) is not prepared"
        case .noFileLoaded:
            return "No file loaded"
        case .unsupported(let message):
            return message
        }
    }
}

class PlaybackCoordinator: ObservableObject {
    @Published var state: PlaybackState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var statusMessage: String = "Idle"

    private let logger = PlayerLogger.shared
    private let router = DecoderRouter()
    private let sourcePreparer = SourcePreparer()
    private var preparedSource: PreparedSource?
    private var route: PlaybackRoute?
    private var backend: PlaybackBackend?
    private var positionTimer: Timer?
    private var currentURL: URL?
    private var volume: Float = 1.0

    init() {
        logger.info(category: "player", message: "PlaybackCoordinator initialized")
    }

    func open(url: URL) {
        stop(unloadSource: true)
        currentURL = url
        currentTime = 0
        duration = 0
        statusMessage = "Loading"
        transition(to: .loading, reason: "open")

        logger.info(category: "source", message: "input URL=\(url.path)")

        do {
            let prepared = try sourcePreparer.prepare(url: url)
            preparedSource = prepared

            let selectedRoute = try router.selectBackend(for: prepared.playingURL)
            route = selectedRoute

            logger.info(
                category: "source",
                message: "detected extension/container=\(selectedRoute.containerDescription) format=\(selectedRoute.format)"
            )
            logger.info(
                category: "player",
                message: "selected backend=\(selectedRoute.backendKind.rawValue) preservesCompressedSource=\(selectedRoute.preservesCompressedSource)"
            )

            let selectedBackend = try makeBackend(for: selectedRoute)
            backend = selectedBackend
            selectedBackend.onFinished = { [weak self] in
                self?.handleFinished()
            }
            selectedBackend.onFailed = { [weak self] error in
                self?.fail(error)
            }
            selectedBackend.setVolume(volume)
            try selectedBackend.prepare(url: prepared.playingURL)

            duration = selectedBackend.duration
            statusMessage = "Ready: \(selectedBackend.name)"
            transition(to: .ready, reason: "prepared")
        } catch {
            fail(error)
        }
    }

    func load(url: URL) {
        open(url: url)
    }

    func play() {
        guard let backend else {
            fail(PlaybackError.noFileLoaded)
            return
        }

        do {
            switch state {
            case .paused:
                try backend.resume()
            case .ready:
                try backend.play()
            case .stopped:
                try backend.seek(to: 0)
                currentTime = 0
                try backend.play()
            case .playing:
                return
            case .idle, .loading, .failed:
                throw PlaybackError.noFileLoaded
            }

            startPositionTimer()
            statusMessage = "Playing: \(backend.name)"
            transition(to: .playing, reason: "play")
        } catch {
            fail(error)
        }
    }

    func pause() {
        guard state == .playing else { return }
        currentTime = backend?.currentTime() ?? currentTime
        backend?.pause()
        stopPositionTimer()
        statusMessage = "Paused"
        transition(to: .paused, reason: "pause")
    }

    func resume() {
        guard state == .paused else {
            play()
            return
        }

        do {
            try backend?.resume()
            startPositionTimer()
            statusMessage = "Playing: \(backend?.name ?? "unknown")"
            transition(to: .playing, reason: "resume")
        } catch {
            fail(error)
        }
    }

    func stop() {
        stop(unloadSource: false)
    }

    func seek(to time: TimeInterval) {
        guard let backend else { return }
        let wasPlaying = state == .playing
        let target = max(0, min(time, duration > 0 ? duration : time))

        do {
            if wasPlaying && backend.seekRequiresRestart {
                backend.pause()
            }
            try backend.seek(to: target)
            currentTime = target
            logger.info(category: "player", message: "seek state=\(state.description) target=\(target)s restart=\(backend.seekRequiresRestart)")
            if wasPlaying && backend.seekRequiresRestart {
                try backend.play()
            }
        } catch {
            fail(error)
        }
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        backend?.setVolume(volume)
    }

    func currentOutputFormat(deviceName: String, hardwareBitDepth: Int?, hardwareIsFloat: Bool) -> OutputFormatInfo? {
        return backend?.currentOutputFormat(deviceName: deviceName, hardwareBitDepth: hardwareBitDepth, hardwareIsFloat: hardwareIsFloat)
    }

    private func stop(unloadSource: Bool) {
        stopPositionTimer()
        backend?.stop()
        currentTime = 0

        if unloadSource {
            if let preparedSource {
                sourcePreparer.cleanup(preparedSource: preparedSource)
            }
            preparedSource = nil
            backend = nil
            route = nil
            currentURL = nil
            duration = 0
            if state != .idle {
                transition(to: .idle, reason: "unload")
            }
            statusMessage = "Idle"
            return
        }

        if state != .idle && state != .stopped {
            statusMessage = "Stopped"
            transition(to: .stopped, reason: "stop")
        }
    }

    private func makeBackend(for route: PlaybackRoute) throws -> PlaybackBackend {
        switch route.backendKind {
        case .nativeFilePlayer:
            return NativeFilePlayerBackend()
        case .pcmEngine:
            return PCMEngineBackend()
        case .ffmpegFallback:
            throw PlaybackRoutingError.ffmpegFallbackReserved(route.format)
        case .unsupported:
            throw PlaybackRoutingError.unsupportedFormat(route.format, currentURL ?? URL(fileURLWithPath: "unknown"))
        }
    }

    private func transition(to newState: PlaybackState, reason: String) {
        let oldState = state
        state = newState
        logger.info(category: "player", message: "state transition \(oldState.description) -> \(newState.description) reason=\(reason)")
    }

    private func fail(_ error: Error) {
        stopPositionTimer()
        backend?.stop()
        let message = error.localizedDescription
        statusMessage = "Unsupported/Failed: \(message)"
        logger.error(category: "player", message: "error message=\(message)")
        transition(to: .failed, reason: "error")
    }

    private func handleFinished() {
        stopPositionTimer()
        currentTime = duration
        backend?.stop()
        statusMessage = "Stopped"
        transition(to: .stopped, reason: "finished")
    }

    private func startPositionTimer() {
        stopPositionTimer()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentTime = self.backend?.currentTime() ?? self.currentTime
            if self.duration == 0, let backendDuration = self.backend?.duration, backendDuration > 0 {
                self.duration = backendDuration
            }
        }
        RunLoop.main.add(positionTimer!, forMode: .common)
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }
}

final class PlaybackController: PlaybackCoordinator {}
