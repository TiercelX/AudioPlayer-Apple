import Foundation
import AVFoundation

class PcmSeekCache {
    struct CacheEntry {
        let positionMs: Int64
        let buffer: AVAudioPCMBuffer
        let timestamp: Date
    }
    
    private var cache: [Int64: CacheEntry] = [:]
    private let maxSize: Int
    private let queue = DispatchQueue(label: "com.audioplayer.seekcache", attributes: .concurrent)
    
    init(maxSize: Int = 1000) {
        self.maxSize = maxSize
    }
    
    func get(positionMs: Int64) -> AVAudioPCMBuffer? {
        return queue.sync {
            return cache[positionMs]?.buffer
        }
    }
    
    func put(positionMs: Int64, buffer: AVAudioPCMBuffer) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Remove oldest entries if cache is full
            if self.cache.count >= self.maxSize {
                let sortedKeys = self.cache.keys.sorted()
                let keysToRemove = sortedKeys.prefix(max(1, self.cache.count - self.maxSize + 1))
                for key in keysToRemove {
                    self.cache.removeValue(forKey: key)
                }
            }
            
            self.cache[positionMs] = CacheEntry(
                positionMs: positionMs,
                buffer: buffer,
                timestamp: Date()
            )
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
    
    func remove(positionMs: Int64) {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeValue(forKey: positionMs)
        }
    }
    
    var count: Int {
        return queue.sync {
            return cache.count
        }
    }
    
    var isEmpty: Bool {
        return queue.sync {
            return cache.isEmpty
        }
    }
}