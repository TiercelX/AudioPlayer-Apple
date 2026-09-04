import Foundation

enum DecoderError: LocalizedError {
    case notOpened
    case bufferCreationFailed
    case readFailed(Error)
    case seekOutOfBounds
    case decodeFailed(Error)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .notOpened:
            return "Decoder is not opened"
        case .bufferCreationFailed:
            return "Failed to create PCM buffer"
        case .readFailed(let error):
            return "Decoder read failed: \(error.localizedDescription)"
        case .seekOutOfBounds:
            return "Seek position is outside the source duration"
        case .decodeFailed(let error):
            return "Decode failed: \(error.localizedDescription)"
        case .unsupportedFormat(let message):
            return message
        }
    }
}
