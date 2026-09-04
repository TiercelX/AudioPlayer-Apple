import Foundation
import os.log

enum LogLevel: String, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warning, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

enum LogCategory: String {
    case player = "player"
    case decoder = "decoder"
    case audio = "audio"
    case ui = "ui"
    case source = "source"
    case artifact = "artifact"
    case system = "system"
}

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let file: String
    let function: String
    let line: Int

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timeStr = formatter.string(from: timestamp)
        return "[\(timeStr)] [\(level.rawValue)] [\(category)] \(message)"
    }

    var json: [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "timestamp": formatter.string(from: timestamp),
            "level": level.rawValue,
            "category": category,
            "message": message,
            "file": URL(fileURLWithPath: file).lastPathComponent,
            "function": function,
            "line": line
        ]
    }
}

class PlayerLogger {
    static let shared = PlayerLogger()

    private let osLogger = Logger(subsystem: "com.audioplayer.mac", category: "playback")
    private var entries: [LogEntry] = []
    private let maxEntries = 10000
    private let queue = DispatchQueue(label: "com.audioplayer.logger", qos: .utility)
    private var logFileURL: URL?
    private var minimumLevel: LogLevel = .debug

    init() {
        setupLogFile()
    }

    func log(
        category: String,
        level: LogLevel = .info,
        message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minimumLevel else { return }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line
        )

        queue.async { [weak self] in
            self?.processEntry(entry)
        }
    }

    func debug(category: String, message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(category: category, level: .debug, message: message, file: file, function: function, line: line)
    }

    func info(category: String, message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(category: category, level: .info, message: message, file: file, function: function, line: line)
    }

    func warning(category: String, message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(category: category, level: .warning, message: message, file: file, function: function, line: line)
    }

    func error(category: String, message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(category: category, level: .error, message: message, file: file, function: function, line: line)
    }

    func getEntries(category: String? = nil, level: LogLevel? = nil, limit: Int = 100) -> [LogEntry] {
        return queue.sync {
            var filtered = entries
            if let category = category {
                filtered = filtered.filter { $0.category == category }
            }
            if let level = level {
                filtered = filtered.filter { $0.level >= level }
            }
            return Array(filtered.suffix(limit))
        }
    }

    func getEntriesAsJSON(category: String? = nil, level: LogLevel? = nil, limit: Int = 100) -> [[String: Any]] {
        return getEntries(category: category, level: level, limit: limit).map { $0.json }
    }

    func clearEntries() {
        queue.async { [weak self] in
            self?.entries.removeAll()
        }
    }

    func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
    }

    func exportLogs() -> Data? {
        return queue.sync {
            let jsonArray = entries.map { $0.json }
            return try? JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted)
        }
    }

    // MARK: - Private

    private func processEntry(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        writeToFile(entry: entry)

        switch entry.level {
        case .debug:
            osLogger.debug("\(entry.message, privacy: .public)")
        case .info:
            osLogger.info("\(entry.message, privacy: .public)")
        case .warning:
            osLogger.warning("\(entry.message, privacy: .public)")
        case .error:
            osLogger.error("\(entry.message, privacy: .public)")
        }
    }

    private func setupLogFile() {
        let logsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AudioPlayerMac")
            .appendingPathComponent("logs")

        if let logsDir = logsDir {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            let pid = ProcessInfo.processInfo.processIdentifier

            logFileURL = logsDir.appendingPathComponent("player-\(timestamp)-\(pid).log")
        }
    }

    private func writeToFile(entry: LogEntry) {
        guard let url = logFileURL else { return }
        let line = entry.formatted + "\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
