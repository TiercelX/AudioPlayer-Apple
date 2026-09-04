import Foundation
import os

enum SourcePreparationError: LocalizedError {
    case fileNotFound(URL)
    case directoryInput(URL)
    case remuxFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .directoryInput(let url):
            return "Expected an audio file, got a directory: \(url.path)"
        case .remuxFailed(let url, let reason):
            return "Failed to remux \(url.lastPathComponent): \(reason)"
        }
    }
}

struct PreparedSource {
    let originalURL: URL
    let playingURL: URL
    let wasRemuxed: Bool
    let cleanupRequired: Bool
}

class SourcePreparer {
    private let logger = PlayerLogger.shared
    private var activeRemuxPath: String?

    // Extensions that are raw elementary streams without a container.
    private static let rawStreamExtensions: Set<String> = ["eb3", "eac3"]

    func prepare(url: URL) throws -> PreparedSource {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw SourcePreparationError.fileNotFound(url)
        }

        if isDirectory.boolValue {
            throw SourcePreparationError.directoryInput(url)
        }

        // If this is a raw elementary stream, remux it into an MP4 container
        // so that AVPlayer can play it natively with Dolby Atmos pass-through.
        let ext = url.pathExtension.lowercased()
        if Self.rawStreamExtensions.contains(ext) {
            return try remuxToMP4(url: url)
        }

        return PreparedSource(
            originalURL: url,
            playingURL: url,
            wasRemuxed: false,
            cleanupRequired: false
        )
    }

    func cleanup(preparedSource: PreparedSource) {
        guard preparedSource.cleanupRequired, preparedSource.wasRemuxed else { return }
        let path = preparedSource.playingURL.path
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
            logger.info(category: "source", message: "cleaned up remuxed file \(path)")
        }
        activeRemuxPath = nil
    }

    func cleanupAll() {
        guard let path = activeRemuxPath else { return }
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
            logger.info(category: "source", message: "cleaned up stale remuxed file \(path)")
        }
        activeRemuxPath = nil
    }

    // MARK: - Private

    private func remuxToMP4(url: URL) throws -> PreparedSource {
        let tmpDir = NSTemporaryDirectory()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pid = ProcessInfo.processInfo.processIdentifier
        let tmpPath = (tmpDir as NSString).appendingPathComponent(
            "\(baseName)_\(pid)_remux.mp4"
        )

        // Clean up any previous remux file first.
        cleanupAll()

        logger.info(category: "source", message: "remuxing \(url.lastPathComponent) -> \(tmpPath)")

        guard let durationMs = FFmpegWrapper.remuxToMP4(
            inputPath: url.path,
            outputPath: tmpPath
        ) else {
            throw SourcePreparationError.remuxFailed(
                url,
                "FFmpeg remux returned an error. The file may be corrupt or unsupported."
            )
        }

        let tmpURL = URL(fileURLWithPath: tmpPath)
        activeRemuxPath = tmpPath

        logger.info(category: "source",
                     message: "remux complete duration=\(durationMs)ms output=\(tmpPath)")

        return PreparedSource(
            originalURL: url,
            playingURL: tmpURL,
            wasRemuxed: true,
            cleanupRequired: true
        )
    }
}
