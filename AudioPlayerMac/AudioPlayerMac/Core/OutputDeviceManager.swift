import Foundation
import CoreAudio

struct AudioDevice {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool
    let isOutput: Bool
    let channelCount: Int
    let sampleRate: Double
    let bitDepth: Int
    let isFloat: Bool
}

protocol OutputDeviceManagerDelegate: AnyObject {
    func outputDevicesDidChange(_ devices: [AudioDevice])
    func selectedDeviceDidChange(_ device: AudioDevice)
}

class OutputDeviceManager {
    weak var delegate: OutputDeviceManagerDelegate?
    
    private var devices: [AudioDevice] = []
    private var selectedDeviceID: AudioDeviceID?
    private var defaultDeviceID: AudioDeviceID?
    
    init() {
        refreshDevices()
        setupDeviceListener()
    }
    
    deinit {
        removeDeviceListener()
    }
    
    // MARK: - Public API
    
    func getAvailableDevices() -> [AudioDevice] {
        return devices
    }
    
    func getDefaultDevice() -> AudioDevice? {
        return devices.first { $0.isDefault }
    }
    
    func getSelectedDevice() -> AudioDevice? {
        guard let selectedID = selectedDeviceID else {
            return getDefaultDevice()
        }
        return devices.first { $0.id == selectedID }
    }
    
    func selectDevice(_ device: AudioDevice) {
        selectedDeviceID = device.id
        delegate?.selectedDeviceDidChange(device)
        
        // Set as default output device
        var deviceID = device.id
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
    }
    
    func selectDefaultDevice() {
        if let defaultDevice = getDefaultDevice() {
            selectDevice(defaultDevice)
        }
    }
    
    func refreshDevices() {
        devices = enumerateOutputDevices()
        defaultDeviceID = getDefaultOutputDeviceID()
        
        if selectedDeviceID == nil {
            selectedDeviceID = defaultDeviceID
        }
        
        let currentDevice = devices.first { $0.id == (selectedDeviceID ?? defaultDeviceID) }
        PlayerLogger.shared.info(category: "output", message: "refreshDevices count=\(devices.count) selectedSR=\(currentDevice?.sampleRate ?? 0)")
        delegate?.outputDevicesDidChange(devices)
    }

    /// Set the nominal sample rate of the given output device.
    /// Returns true on success.
    @discardableResult
    func setDeviceSampleRate(_ sampleRate: Double, forDevice deviceID: AudioDeviceID) -> Bool {
        var rate = Float64(sampleRate)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &rate
        )
        PlayerLogger.shared.info(
            category: "output",
            message: "setDeviceSampleRate \(sampleRate)Hz device=\(deviceID) status=\(status)"
        )
        return status == noErr
    }

    /// Set the nominal sample rate of the currently selected (or default) output device.
    @discardableResult
    func setOutputSampleRate(_ sampleRate: Double) -> Bool {
        guard let deviceID = selectedDeviceID ?? defaultDeviceID else { return false }
        return setDeviceSampleRate(sampleRate, forDevice: deviceID)
    }

    /// Set the physical bit depth of the first output stream on the given device.
    @discardableResult
    func setDeviceBitDepth(_ bitDepth: UInt32, forDevice deviceID: AudioDeviceID) -> Bool {
        // Get output stream IDs
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let streamCount = Int(dataSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &dataSize, &streamIDs)
        guard let streamID = streamIDs.first else { return false }

        // Get current physical format
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(streamID, &formatAddress, 0, nil, &dataSize, &format)
        guard status == noErr else { return false }

        format.mBitsPerChannel = bitDepth
        status = AudioObjectSetPropertyData(streamID, &formatAddress, 0, nil, dataSize, &format)
        PlayerLogger.shared.info(
            category: "output",
            message: "setDeviceBitDepth \(bitDepth)bit device=\(deviceID) stream=\(streamID) status=\(status)"
        )
        return status == noErr
    }

    /// Set the physical bit depth of the currently selected (or default) output device.
    @discardableResult
    func setOutputBitDepth(_ bitDepth: UInt32) -> Bool {
        guard let deviceID = selectedDeviceID ?? defaultDeviceID else { return false }
        return setDeviceBitDepth(bitDepth, forDevice: deviceID)
    }

    // MARK: - Private Implementation
    
    private func enumerateOutputDevices() -> [AudioDevice] {
        var deviceIDs: [AudioDeviceID] = []
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        var outputDevices: [AudioDevice] = []
        
        for deviceID in deviceIDs {
            if isOutputDevice(deviceID) {
                let device = createAudioDevice(from: deviceID)
                outputDevices.append(device)
            }
        }
        
        return outputDevices
    }
    
    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return false }
        
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )
        
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        for buffer in bufferList {
            if buffer.mNumberChannels > 0 {
                return true
            }
        }
        
        return false
    }
    
    private func createAudioDevice(from deviceID: AudioDeviceID) -> AudioDevice {
        let name = getDeviceName(deviceID) ?? "Unknown Device"
        let isDefault = deviceID == defaultDeviceID
        let channelCount = getDeviceChannelCount(deviceID)
        let sampleRate = getDeviceSampleRate(deviceID)
        let physical = getDevicePhysicalFormat(deviceID)

        return AudioDevice(
            id: deviceID,
            name: name,
            isDefault: isDefault,
            isOutput: true,
            channelCount: channelCount,
            sampleRate: sampleRate,
            bitDepth: physical.bitDepth,
            isFloat: physical.isFloat
        )
    }

    private func getDevicePhysicalFormat(_ deviceID: AudioDeviceID) -> (bitDepth: Int, isFloat: Bool) {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return (0, false) }

        let streamCount = Int(dataSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &dataSize, &streamIDs)
        guard let streamID = streamIDs.first else { return (0, false) }

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(streamID, &formatAddress, 0, nil, &dataSize, &format)
        guard status == noErr else { return (0, false) }

        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        return (Int(format.mBitsPerChannel), isFloat)
    }
    
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return nil }
        
        var name: CFString = "" as CFString
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )
        
        return name as String
    }
    
    private func getDeviceChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return 0 }
        
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )
        
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        var channelCount = 0
        for buffer in bufferList {
            channelCount += Int(buffer.mNumberChannels)
        }
        
        return channelCount
    }
    
    private func getDeviceSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return 0 }
        
        var sampleRate: Float64 = 0
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &sampleRate
        )
        
        return sampleRate
    }
    
    private func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = kAudioDeviceUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        guard status == noErr, deviceID != kAudioDeviceUnknown else {
            return nil
        }
        
        return deviceID
    }
    
    // MARK: - Device Change Listener
    
    private func setupDeviceListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }
        
        // Listen for default device changes
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.defaultDeviceID = self?.getDefaultOutputDeviceID()
            if let self = self, let device = self.getSelectedDevice() {
                self.delegate?.selectedDeviceDidChange(device)
            }
        }

        // Listen for sample rate changes on the default output device
        setupSampleRateListener()
    }

    private var sampleRateListenerDeviceID: AudioDeviceID?

    private func setupSampleRateListener() {
        removeSampleRateListener()
        guard let deviceID = selectedDeviceID ?? defaultDeviceID else { return }
        sampleRateListenerDeviceID = deviceID
        PlayerLogger.shared.info(category: "output", message: "setupSampleRateListener deviceID=\(deviceID)")
        var srAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &srAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            PlayerLogger.shared.info(category: "output", message: "sample rate changed on device=\(deviceID)")
            self?.refreshDevices()
        }
    }

    private func removeSampleRateListener() {
        guard let deviceID = sampleRateListenerDeviceID else { return }
        var srAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            deviceID,
            &srAddress,
            DispatchQueue.main
        ) { _, _ in }
        sampleRateListenerDeviceID = nil
    }
    
    private func removeDeviceListener() {
        removeSampleRateListener()
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { _, _ in }
        
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main
        ) { _, _ in }
    }
}
