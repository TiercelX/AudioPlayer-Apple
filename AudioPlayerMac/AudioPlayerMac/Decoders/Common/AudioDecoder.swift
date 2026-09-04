import AVFoundation

protocol AudioDecoder {
    func open(url: URL) throws
    func decode() throws -> AVAudioPCMBuffer?
    func seek(to positionMs: Int64) throws
    func close()
}
