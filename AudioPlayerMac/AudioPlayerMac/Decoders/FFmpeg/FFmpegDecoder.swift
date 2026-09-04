import Foundation
import AVFoundation

class FFmpegDecoder: AudioDecoder {
    private var wrapper: FFmpegWrapper?
    private var isOpen = false
    private var currentPositionMs: Int64 = 0
    private(set) var seekCache = PcmSeekCache()
    
    func open(url: URL) throws {
        wrapper = FFmpegWrapper()
        try wrapper?.open(url: url)
        isOpen = true
        currentPositionMs = 0
        seekCache = PcmSeekCache()
    }
    
    func decode() throws -> AVAudioPCMBuffer? {
        guard isOpen, let wrapper = wrapper else {
            throw DecoderError.notOpened
        }
        
        let bufferPositionMs = currentPositionMs
        let buffer = try wrapper.decode()
        if let buffer = buffer {
            let sampleRate = wrapper.getSampleRate()
            if sampleRate > 0 {
                let frameDurationMs = Int64(Double(buffer.frameLength) / Double(sampleRate) * 1000.0)
                currentPositionMs += frameDurationMs
                seekCache.put(positionMs: bufferPositionMs, buffer: buffer)
            }
        }
        return buffer
    }
    
    func seek(to positionMs: Int64) throws {
        guard isOpen, let wrapper = wrapper else {
            throw DecoderError.notOpened
        }
        
        let tolerance: Int64 = 1000
        if let _ = findCacheHit(near: positionMs, tolerance: tolerance) {
            PlayerLogger.shared.info(category: "decoder", message: "Seek cache hit near \(positionMs)ms")
        }
        
        try wrapper.seek(to: positionMs)
        currentPositionMs = positionMs
    }
    
    func close() {
        wrapper?.close()
        wrapper = nil
        isOpen = false
        currentPositionMs = 0
        seekCache.clear()
    }
    
    var durationMs: Int64 {
        guard let wrapper = wrapper else { return 0 }
        return wrapper.getDurationMs()
    }
    
    var currentPositionMsValue: Int64 {
        return currentPositionMs
    }

    var sampleRate: Int {
        return wrapper?.getSampleRate() ?? 0
    }

    var channels: Int {
        return wrapper?.getChannels() ?? 0
    }
    
    private func findCacheHit(near positionMs: Int64, tolerance: Int64) -> AVAudioPCMBuffer? {
        let exact = seekCache.get(positionMs: positionMs)
        if exact != nil { return exact }
        for offset in 1...tolerance {
            if let hit = seekCache.get(positionMs: positionMs + offset) { return hit }
            if let hit = seekCache.get(positionMs: positionMs - offset) { return hit }
        }
        return nil
    }
}