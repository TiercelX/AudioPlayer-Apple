import Foundation
import AVFoundation
import UniformTypeIdentifiers
import AppKit
import Combine

class AppState: ObservableObject {
    @Published var currentFile: URL?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0
    @Published var playbackStatus: String = "Idle"
    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var selectedOutputDevice: AudioDevice?
    @Published var currentMediaInfo: MediaInfo?
    @Published var precisePlayback: Bool = false
    @Published var currentOutputInfo: OutputFormatInfo?

    private var playbackController: PlaybackCoordinator?
    private(set) var outputDeviceManager: OutputDeviceManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupAudio()
        setupOutputDeviceManager()
        handleCommandLineArguments()
    }

    private func handleCommandLineArguments() {
        let args = CommandLine.arguments
        if args.count > 1 {
            let filePath = args[1]
            let url = URL(fileURLWithPath: filePath)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.loadFile(url: url)
            }
        }
    }

    private func setupAudio() {
        playbackController = PlaybackCoordinator()

        playbackController?.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isPlaying = (state == .playing)
            }
            .store(in: &cancellables)

        playbackController?.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.currentTime = time
            }
            .store(in: &cancellables)

        playbackController?.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                self?.duration = dur
            }
            .store(in: &cancellables)

        playbackController?.$statusMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.playbackStatus = message
            }
            .store(in: &cancellables)
    }

    private func setupOutputDeviceManager() {
        outputDeviceManager = OutputDeviceManager()
        outputDeviceManager?.delegate = self
        
        if let devices = outputDeviceManager?.getAvailableDevices() {
            availableOutputDevices = devices
        }
        
        selectedOutputDevice = outputDeviceManager?.getSelectedDevice()
    }

    func openFile() {
        let panel = NSOpenPanel()
        // Allow standard audio plus raw Dolby stream extensions (.eb3/.eac3)
        // that macOS does not recognise as .audio.
        let eb3Type = UTType(filenameExtension: "eb3") ?? .data
        let eac3Type = UTType(filenameExtension: "eac3") ?? .data
        panel.allowedContentTypes = [.audio, eb3Type, eac3Type]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            if let url = panel.url {
                loadFile(url: url)
            }
        }
    }

    /// Whether the player is in an active state (playing or paused).
    var isActive: Bool {
        isPlaying || playbackStatus == "Paused"
    }

    func loadFile(url: URL) {
        currentFile = url
        currentMediaInfo = MediaInfo.from(url: url)
        playbackController?.load(url: url)
        updateOutputInfo()
        play()
    }

    func play() {
        if precisePlayback, let info = currentMediaInfo, info.sampleRate > 0 {
            outputDeviceManager?.setOutputSampleRate(info.sampleRate)
            if info.bitDepth > 0 {
                outputDeviceManager?.setOutputBitDepth(UInt32(info.bitDepth))
            }
        }
        playbackController?.play()
        updateOutputInfo()
    }

    /// Query the actual output format after playback starts.
    func updateOutputInfo() {
        let device = selectedOutputDevice ?? outputDeviceManager?.getDefaultDevice()
        guard let device = device else {
            currentOutputInfo = nil
            return
        }
        currentOutputInfo = OutputFormatInfo(
            sampleRate: device.sampleRate,
            channelCount: device.channelCount,
            bitDepth: device.bitDepth > 0 ? device.bitDepth : 0,
            isFloat: device.isFloat,
            deviceName: device.name
        )
    }

    func pause() {
        playbackController?.pause()
    }

    func stop() {
        playbackController?.stop()
        currentOutputInfo = nil
    }

    func seek(to time: TimeInterval) {
        playbackController?.seek(to: time)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        playbackController?.setVolume(volume)
    }
    
    func selectOutputDevice(_ device: AudioDevice) {
        outputDeviceManager?.selectDevice(device)
        selectedOutputDevice = device
        updateOutputInfo()
    }
}

extension AppState: OutputDeviceManagerDelegate {
    func outputDevicesDidChange(_ devices: [AudioDevice]) {
        DispatchQueue.main.async { [weak self] in
            self?.availableOutputDevices = devices
            // Refresh the cached selectedOutputDevice (value type) with fresh data
            if let self = self, let id = self.selectedOutputDevice?.id {
                self.selectedOutputDevice = devices.first { $0.id == id }
            }
            self?.updateOutputInfo()
        }
    }
    
    func selectedDeviceDidChange(_ device: AudioDevice) {
        DispatchQueue.main.async { [weak self] in
            self?.selectedOutputDevice = device
        }
    }
}
