# PCM Seek Cache

## Overview

The PCM Seek Cache stores decoded PCM data to enable fast seeking without re-decoding from the beginning. It uses a segment-based approach with LRU (Least Recently Used) eviction.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    PcmSeekCache                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  Segment 1  │  │  Segment 2  │  │  Segment 3  │     │
│  │  pos: 0ms   │  │  pos: 500ms │  │  pos: 1000ms│     │
│  │  size: 1MB  │  │  size: 1MB  │  │  size: 1MB  │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│         │                │                │              │
│         └────────────────┼────────────────┘              │
│                          ▼                               │
│                   ┌─────────────┐                        │
│                   │ Memory or   │                        │
│                   │ Disk Buffer │                        │
│                   └─────────────┘                        │
└─────────────────────────────────────────────────────────┘
```

## Storage modes

| Mode | Description | Use case |
|------|-------------|----------|
| **Memory** | Store in RAM | Small files, fast access |
| **Disk** | Store on disk | Large files, persistent |
| **Disabled** | No caching | Low memory systems |

### Mode selection

```swift
func detectStorageMode(requestedMiB: Int) -> StorageMode {
    let availableMemory = ProcessInfo.processInfo.physicalMemory
    let requestedBytes = Int64(requestedMiB) * 1024 * 1024
    
    // Use memory if available
    if availableMemory > requestedBytes + 128 * 1024 * 1024 {
        return .memory
    }
    
    // Otherwise use disk
    return .disk
}
```

## Data structures

### Segment

```swift
struct Segment {
    let positionMs: Int64        // Start position in milliseconds
    let durationMs: Int64        // Duration in milliseconds
    let byteOffset: Int          // Offset in buffer
    let byteSize: Int            // Size in bytes
    var lastAccessTime: Date     // For LRU eviction
}
```

### Cache key

```swift
struct CacheKey: Hashable {
    let sourcePath: String       // File path
    let sampleRate: Int          // Sample rate
    let channelCount: Int        // Channel count
    let bitsPerSample: Int       // Bits per sample
    
    func toHash() -> String {
        let input = "\(sourcePath)|\(sampleRate)|\(channelCount)|\(bitsPerSample)|pcm-seek"
        return input.sha1() // Or use CryptoKit
    }
}
```

## Implementation

### PcmSeekCache.swift

```swift
// AudioPlayerMac/Decoders/Common/PcmSeekCache.swift

import Foundation

class PcmSeekCache {
    enum StorageMode {
        case memory
        case disk
        case disabled
    }
    
    struct Segment {
        let positionMs: Int64
        let durationMs: Int64
        let byteOffset: Int
        let byteSize: Int
        var lastAccessTime: Date
    }
    
    struct Hit {
        let positionMs: Int64
        let durationMs: Int64
        let byteOffset: Int
        let byteSize: Int
        let valid: Bool
    }
    
    private var segments: [Segment] = []
    private var storageMode: StorageMode = .disabled
    private var memoryBuffer: Data?
    private var memoryCapacity: Int = 0
    private var diskPath: URL?
    private var diskFileHandle: FileHandle?
    private var totalCachedBytes: Int = 0
    private var initialized: Bool = false
    
    private let lock = NSLock()
    
    // Default capacity: 256 MB
    private let defaultMemoryCapacity = 256 * 1024 * 1024
    
    /// Initialize the cache
    /// - Parameters:
    ///   - sourcePath: Path to the source audio file
    ///   - format: PCM format description
    ///   - cacheRoot: Root directory for disk cache
    ///   - maxCacheMiB: Maximum cache size in MB
    ///   - maxAgeMinutes: Maximum age for cached segments
    func initialize(sourcePath: String,
                    format: PcmStreamFormat,
                    cacheRoot: String,
                    maxCacheMiB: Int = 256,
                    maxAgeMinutes: Int = 30) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Create cache key
        let key = createCacheKey(sourcePath: sourcePath, format: format)
        
        // Detect storage mode
        storageMode = detectStorageMode(requestedMiB: maxCacheMiB)
        
        switch storageMode {
        case .memory:
            memoryCapacity = maxCacheMiB * 1024 * 1024
            memoryBuffer = Data(capacity: memoryCapacity)
            
        case .disk:
            let cacheDir = URL(fileURLWithPath: cacheRoot)
                .appendingPathComponent("pcm-cache")
            try? FileManager.default.createDirectory(at: cacheDir, 
                                                    withIntermediateDirectories: true)
            
            diskPath = cacheDir.appendingPathComponent("\(key).pcm-cache")
            
            // Create or open cache file
            if !FileManager.default.fileExists(atPath: diskPath!.path) {
                FileManager.default.createFile(atPath: diskPath!.path, contents: nil)
            }
            
            diskFileHandle = try? FileHandle(forUpdating: diskPath!)
            
        case .disabled:
            break
        }
        
        // Prune old segments
        pruneByAge(maxAgeMinutes: maxAgeMinutes)
        
        initialized = true
        return true
    }
    
    /// Write PCM data to cache
    /// - Parameters:
    ///   - positionMs: Position in milliseconds
    ///   - pcmData: PCM data to cache
    ///   - format: PCM format description
    func writeSegment(positionMs: Int64, pcmData: Data, format: PcmStreamFormat) {
        lock.lock()
        defer { lock.unlock() }
        
        guard initialized && storageMode != .disabled else { return }
        
        let durationMs = calculateDuration(dataSize: pcmData.count, format: format)
        let segment = Segment(
            positionMs: positionMs,
            durationMs: durationMs,
            byteOffset: totalCachedBytes,
            byteSize: pcmData.count,
            lastAccessTime: Date()
        )
        
        switch storageMode {
        case .memory:
            guard let buffer = memoryBuffer else { return }
            
            // Check capacity
            if totalCachedBytes + pcmData.count > memoryCapacity {
                pruneByBytes(targetBytes: memoryCapacity - pcmData.count)
            }
            
            // Append to buffer
            memoryBuffer?.append(pcmData)
            
        case .disk:
            guard let handle = diskFileHandle else { return }
            
            // Seek to end
            handle.seekToEndOfFile()
            handle.write(pcmData)
            try? handle.synchronize()
            
        case .disabled:
            return
        }
        
        segments.append(segment)
        totalCachedBytes += pcmData.count
    }
    
    /// Find cached data for a target position
    /// - Parameters:
    ///   - targetMs: Target position in milliseconds
    ///   - toleranceMs: Tolerance for matching (default 1000ms)
    /// - Returns: Hit if found, nil otherwise
    func findHit(targetMs: Int64, toleranceMs: Int64 = 1000) -> Hit? {
        lock.lock()
        defer { lock.unlock() }
        
        guard initialized else { return nil }
        
        // Search from newest to oldest
        for i in stride(from: segments.count - 1, through: 0, by: -1) {
            let segment = segments[i]
            
            // Check if target falls within segment
            if segment.positionMs <= targetMs &&
               targetMs < segment.positionMs + segment.durationMs + toleranceMs {
                
                // Update last access time
                segments[i].lastAccessTime = Date()
                
                return Hit(
                    positionMs: segment.positionMs,
                    durationMs: segment.durationMs,
                    byteOffset: segment.byteOffset,
                    byteSize: segment.byteSize,
                    valid: true
                )
            }
            
            // Stop if we've passed the target
            if segment.positionMs > targetMs + toleranceMs {
                break
            }
        }
        
        return nil
    }
    
    /// Read cached PCM data
    /// - Parameter hit: Hit from findHit
    /// - Returns: PCM data, or nil if not found
    func readSegment(hit: Hit) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        
        guard initialized && hit.valid else { return nil }
        
        switch storageMode {
        case .memory:
            guard let buffer = memoryBuffer else { return nil }
            let start = hit.byteOffset
            let end = start + hit.byteSize
            guard end <= buffer.count else { return nil }
            return buffer[start..<end]
            
        case .disk:
            guard let handle = diskFileHandle else { return nil }
            handle.seek(toFileOffset: UInt64(hit.byteOffset))
            return handle.readData(ofLength: hit.byteSize)
            
        case .disabled:
            return nil
        }
    }
    
    /// Clear all cached data
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        segments.removeAll()
        totalCachedBytes = 0
        
        switch storageMode {
        case .memory:
            memoryBuffer?.removeAll()
            
        case .disk:
            if let path = diskPath {
                try? FileManager.default.removeItem(at: path)
                FileManager.default.createFile(atPath: path.path, contents: nil)
                diskFileHandle = try? FileHandle(forUpdating: path)
            }
            
        case .disabled:
            break
        }
    }
    
    func isInitialized() -> Bool { return initialized }
    func totalBytes() -> Int { return totalCachedBytes }
    func segmentCount() -> Int { return segments.count }
    
    // MARK: - Private
    
    private func createCacheKey(sourcePath: String, format: PcmStreamFormat) -> String {
        let input = "\(sourcePath)|\(format.sampleRate)|\(format.channelCount)|\(format.bitsPerSample)|pcm-seek"
        return input.sha1()
    }
    
    private func detectStorageMode(requestedMiB: Int) -> StorageMode {
        guard requestedMiB > 0 else { return .disabled }
        
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        let requestedBytes = Int64(requestedMiB) * 1024 * 1024
        
        if availableMemory > requestedBytes + 128 * 1024 * 1024 {
            return .memory
        }
        
        return .disk
    }
    
    private func calculateDuration(dataSize: Int, format: PcmStreamFormat) -> Int64 {
        let bytesPerFrame = format.channelCount * (format.bitsPerSample / 8)
        guard bytesPerFrame > 0 else { return 0 }
        
        let frameCount = dataSize / bytesPerFrame
        return Int64(Double(frameCount) / Double(format.sampleRate) * 1000)
    }
    
    private func pruneByAge(maxAgeMinutes: Int) {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeMinutes) * 60)
        segments.removeAll { $0.lastAccessTime < cutoff }
        recalculateTotalBytes()
    }
    
    private func pruneByBytes(targetBytes: Int) {
        while totalCachedBytes > targetBytes && !segments.isEmpty {
            evictOldestSegment()
        }
    }
    
    private func evictOldestSegment() {
        guard !segments.isEmpty else { return }
        
        // Find oldest segment
        var oldestIndex = 0
        var oldestTime = segments[0].lastAccessTime
        
        for i in 1..<segments.count {
            if segments[i].lastAccessTime < oldestTime {
                oldestTime = segments[i].lastAccessTime
                oldestIndex = i
            }
        }
        
        let removed = segments.remove(at: oldestIndex)
        totalCachedBytes -= removed.byteSize
    }
    
    private func recalculateTotalBytes() {
        totalCachedBytes = segments.reduce(0) { $0 + $1.byteSize }
    }
    
    deinit {
        diskFileHandle?.closeFile()
    }
}

// MARK: - Helper extensions

extension String {
    func sha1() -> String {
        // Use CryptoKit or implement SHA1
        // For simplicity, use a basic hash
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: 20)
        data.withUnsafeBytes { ptr in
            for (i, byte) in ptr.enumerated() {
                hash[i % 20] = hash[i % 20] &+ byte
            }
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
```

## Usage example

```swift
// Create cache
let cache = PcmSeekCache()

// Initialize
let format = PcmStreamFormat(
    sampleRate: 48000,
    channelCount: 2,
    bitsPerSample: 32
)

cache.initialize(
    sourcePath: "/path/to/audio.eac3",
    format: format,
    cacheRoot: "/path/to/cache",
    maxCacheMiB: 256,
    maxAgeMinutes: 30
)

// Write decoded PCM to cache
let pcmData: Data = ... // Decoded PCM data
cache.writeSegment(positionMs: 0, pcmData: pcmData, format: format)

// Seek: check cache first
if let hit = cache.findHit(targetMs: 5000) {
    if let cachedData = cache.readSegment(hit: hit) {
        // Use cached data, continue decoding from hit.positionMs + hit.durationMs
    }
}

// Clear cache
cache.clear()
```

## Integration with decoder

```swift
class FFmpegDecoder {
    private var seekCache: PcmSeekCache?
    
    func seek(to positionMs: Int64) throws {
        // Check cache first
        if let cache = seekCache,
           let hit = cache.findHit(targetMs: positionMs) {
            // Use cached data
            let cachedData = cache.readSegment(hit: hit)
            // Continue decoding from cached position
        } else {
            // Seek and decode from beginning
            try wrapper?.seek(to: positionMs)
            // Decode and cache
        }
    }
    
    func decode() throws -> AVAudioPCMBuffer? {
        let buffer = try wrapper?.decode()
        
        // Cache decoded data
        if let data = buffer?.toData() {
            seekCache?.writeSegment(
                positionMs: currentPositionMs,
                pcmData: data,
                format: currentFormat
            )
        }
        
        return buffer
    }
}
```

## Performance considerations

- **Memory mode**: Fastest, but limited by available RAM
- **Disk mode**: Slower, but can cache large files
- **Segment size**: Larger segments = fewer seeks, but more memory usage
- **LRU eviction**: Keeps most recently used segments

## Testing

```swift
func testPcmSeekCache() {
    let cache = PcmSeekCache()
    let format = PcmStreamFormat(sampleRate: 48000, channelCount: 2, bitsPerSample: 32)
    
    // Initialize
    assert(cache.initialize(sourcePath: "test.wav", format: format, cacheRoot: "/tmp"))
    
    // Write
    let data = Data(repeating: 0, count: 48000 * 2 * 4) // 1 second
    cache.writeSegment(positionMs: 0, pcmData: data, format: format)
    
    // Read
    let hit = cache.findHit(targetMs: 500)
    assert(hit != nil)
    assert(hit!.positionMs == 0)
    
    let readData = cache.readSegment(hit: hit!)
    assert(readData == data)
    
    // Clear
    cache.clear()
    assert(cache.segmentCount() == 0)
}
```

## See also

- Architecture overview: `docs/dev/architecture.md`
- Decoder path selection: `docs/dev/decoder-paths.md`
