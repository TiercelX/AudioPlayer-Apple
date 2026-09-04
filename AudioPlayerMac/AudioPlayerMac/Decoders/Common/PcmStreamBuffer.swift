import Foundation
import AVFoundation

class PcmStreamBuffer {
    private var buffer: AVAudioPCMBuffer?
    private(set) var format: AVAudioFormat
    private let capacity: AVAudioFrameCount
    private var writePosition: AVAudioFrameCount = 0
    private var readPosition: AVAudioFrameCount = 0
    private var availableFrames: AVAudioFrameCount = 0
    private let queue = DispatchQueue(label: "com.audioplayer.streambuffer")
    
    init(format: AVAudioFormat, capacity: AVAudioFrameCount = 44100 * 2) {
        self.format = format
        self.capacity = capacity
        self.buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
    }
    
    var framesAvailable: AVAudioFrameCount {
        return queue.sync {
            return availableFrames
        }
    }
    
    var isFull: Bool {
        return queue.sync {
            return availableFrames >= capacity
        }
    }
    
    var isEmpty: Bool {
        return queue.sync {
            return availableFrames == 0
        }
    }
    
    func write(buffer inputBuffer: AVAudioPCMBuffer) -> Bool {
        return queue.sync {
            guard let buffer = buffer else { return false }
            
            guard inputBuffer.format.channelCount == format.channelCount else {
                PlayerLogger.shared.error(
                    category: "buffer",
                    message: "PCM channel mismatch: input=\(inputBuffer.format.channelCount), buffer=\(format.channelCount)"
                )
                return false
            }

            let framesToWrite = min(inputBuffer.frameLength, capacity - availableFrames)
            guard framesToWrite > 0 else { return false }
            
            let channelCount = Int(format.channelCount)
            let firstSegmentFrames = min(framesToWrite, capacity - writePosition)
            let secondSegmentFrames = framesToWrite - firstSegmentFrames
            
            for channel in 0..<channelCount {
                if let inputData = inputBuffer.floatChannelData?[channel],
                   let outputData = buffer.floatChannelData?[channel] {
                    memcpy(
                        outputData.advanced(by: Int(writePosition)),
                        inputData,
                        Int(firstSegmentFrames) * MemoryLayout<Float>.size
                    )
                    if secondSegmentFrames > 0 {
                        memcpy(
                            outputData,
                            inputData.advanced(by: Int(firstSegmentFrames)),
                            Int(secondSegmentFrames) * MemoryLayout<Float>.size
                        )
                    }
                }
            }
            
            writePosition = (writePosition + framesToWrite) % capacity
            availableFrames += framesToWrite
            buffer.frameLength = min(capacity, max(buffer.frameLength, availableFrames))
            
            return true
        }
    }
    
    func read(frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        return queue.sync {
            guard let buffer = buffer else { return nil }
            
            let framesToRead = min(frameCount, availableFrames)
            guard framesToRead > 0 else { return nil }
            
            let readBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead)
            readBuffer?.frameLength = framesToRead
            
            let channelCount = Int(format.channelCount)
            let firstSegmentFrames = min(framesToRead, capacity - readPosition)
            let secondSegmentFrames = framesToRead - firstSegmentFrames
            
            for channel in 0..<channelCount {
                if let sourceData = buffer.floatChannelData?[channel],
                   let destData = readBuffer?.floatChannelData?[channel] {
                    memcpy(
                        destData,
                        sourceData.advanced(by: Int(readPosition)),
                        Int(firstSegmentFrames) * MemoryLayout<Float>.size
                    )
                    if secondSegmentFrames > 0 {
                        memcpy(
                            destData.advanced(by: Int(firstSegmentFrames)),
                            sourceData,
                            Int(secondSegmentFrames) * MemoryLayout<Float>.size
                        )
                    }
                }
            }
            
            readPosition = (readPosition + framesToRead) % capacity
            availableFrames -= framesToRead
            
            if availableFrames == 0 {
                writePosition = 0
                readPosition = 0
                buffer.frameLength = 0
            }
            
            return readBuffer
        }
    }

    func read(into audioBufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: AVAudioFrameCount) -> AVAudioFrameCount {
        return queue.sync {
            guard let buffer = buffer else { return 0 }

            let outputBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let channelCount = min(Int(format.channelCount), outputBuffers.count)
            let requestedFrames = Int(frameCount)
            guard requestedFrames > 0, channelCount > 0 else { return 0 }

            for channel in 0..<channelCount {
                guard let outputData = outputBuffers[channel].mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }
                memset(outputData, 0, requestedFrames * MemoryLayout<Float>.size)
                outputBuffers[channel].mDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
            }

            let framesToRead = min(frameCount, availableFrames)
            guard framesToRead > 0 else { return 0 }

            let firstSegmentFrames = min(framesToRead, capacity - readPosition)
            let secondSegmentFrames = framesToRead - firstSegmentFrames

            for channel in 0..<channelCount {
                guard let sourceData = buffer.floatChannelData?[channel],
                      let outputData = outputBuffers[channel].mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                memcpy(
                    outputData,
                    sourceData.advanced(by: Int(readPosition)),
                    Int(firstSegmentFrames) * MemoryLayout<Float>.size
                )
                if secondSegmentFrames > 0 {
                    memcpy(
                        outputData.advanced(by: Int(firstSegmentFrames)),
                        sourceData,
                        Int(secondSegmentFrames) * MemoryLayout<Float>.size
                    )
                }
            }

            readPosition = (readPosition + framesToRead) % capacity
            availableFrames -= framesToRead

            if availableFrames == 0 {
                writePosition = 0
                readPosition = 0
                buffer.frameLength = 0
            }

            return framesToRead
        }
    }
    
    func clear() {
        queue.sync {
            writePosition = 0
            readPosition = 0
            availableFrames = 0
            buffer?.frameLength = 0
        }
    }
    
    func reset() {
        queue.sync {
            writePosition = 0
            readPosition = 0
            availableFrames = 0
            buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        }
    }
}
