import Foundation

struct DiagnosticReport {
    let timestamp: Date
    let sessionId: String
    let systemInfo: SystemInfo
    let playbackState: PlaybackStateInfo
    let audioLevels: AudioLevelInfo
    let artifacts: ArtifactInfo
    let logEntries: [LogEntryInfo]
    let performance: PerformanceInfo

    struct SystemInfo {
        let macOSVersion: String
        let hardwareModel: String
        let cpuCount: Int
        let totalMemoryMB: Int
        let appVersion: String
    }

    struct PlaybackStateInfo {
        let state: String
        let currentFile: String?
        let format: String?
        let sampleRate: Double?
        let channelCount: Int?
        let bitDepth: Int?
        let durationSeconds: Double?
        let currentPositionSeconds: Double?
    }

    struct AudioLevelInfo {
        let leftPeak: Float
        let rightPeak: Float
        let leftRMS: Float
        let rightRMS: Float
    }

    struct ArtifactInfo {
        let totalArtifacts: UInt64
        let artifactsByType: [String: UInt64]
        let recentEvents: [ArtifactEventInfo]
    }

    struct ArtifactEventInfo {
        let type: String
        let severity: String
        let magnitude: Double
        let positionMs: Int64
        let timestamp: String
    }

    struct LogEntryInfo {
        let timestamp: String
        let level: String
        let category: String
        let message: String
    }

    struct PerformanceInfo {
        let memoryUsageMB: Double
        let cpuUsagePercent: Double
        let bufferUnderruns: Int
        let averageDecodeTimeMs: Double
    }

    func toJSON() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "timestamp": formatter.string(from: timestamp),
            "sessionId": sessionId,
            "system": [
                "macOSVersion": systemInfo.macOSVersion,
                "hardwareModel": systemInfo.hardwareModel,
                "cpuCount": systemInfo.cpuCount,
                "totalMemoryMB": systemInfo.totalMemoryMB,
                "appVersion": systemInfo.appVersion
            ],
            "playback": [
                "state": playbackState.state,
                "currentFile": playbackState.currentFile as Any,
                "format": playbackState.format as Any,
                "sampleRate": playbackState.sampleRate as Any,
                "channelCount": playbackState.channelCount as Any,
                "bitDepth": playbackState.bitDepth as Any,
                "durationSeconds": playbackState.durationSeconds as Any,
                "currentPositionSeconds": playbackState.currentPositionSeconds as Any
            ],
            "audioLevels": [
                "leftPeak": audioLevels.leftPeak,
                "rightPeak": audioLevels.rightPeak,
                "leftRMS": audioLevels.leftRMS,
                "rightRMS": audioLevels.rightRMS
            ],
            "artifacts": [
                "totalArtifacts": artifacts.totalArtifacts,
                "artifactsByType": artifacts.artifactsByType,
                "recentEvents": artifacts.recentEvents.map { [
                    "type": $0.type,
                    "severity": $0.severity,
                    "magnitude": $0.magnitude,
                    "positionMs": $0.positionMs,
                    "timestamp": $0.timestamp
                ]}
            ],
            "performance": [
                "memoryUsageMB": performance.memoryUsageMB,
                "cpuUsagePercent": performance.cpuUsagePercent,
                "bufferUnderruns": performance.bufferUnderruns,
                "averageDecodeTimeMs": performance.averageDecodeTimeMs
            ]
        ]
    }

    func toJSONData() -> Data? {
        return try? JSONSerialization.data(withJSONObject: toJSON(), options: .prettyPrinted)
    }

    func toJSONString() -> String? {
        guard let data = toJSONData() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

class DiagnosticReportBuilder {
    private var sessionId: String = UUID().uuidString
    private var playbackState: DiagnosticReport.PlaybackStateInfo?
    private var audioLevels: DiagnosticReport.AudioLevelInfo?
    private var artifactMonitor: AudioArtifactMonitor?
    private var additionalEntries: [(String, LogLevel, String)] = []

    func setSessionId(_ id: String) {
        sessionId = id
    }

    func setPlaybackState(
        state: String,
        currentFile: String? = nil,
        format: String? = nil,
        sampleRate: Double? = nil,
        channelCount: Int? = nil,
        bitDepth: Int? = nil,
        durationSeconds: Double? = nil,
        currentPositionSeconds: Double? = nil
    ) {
        playbackState = DiagnosticReport.PlaybackStateInfo(
            state: state,
            currentFile: currentFile,
            format: format,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitDepth: bitDepth,
            durationSeconds: durationSeconds,
            currentPositionSeconds: currentPositionSeconds
        )
    }

    func setAudioLevels(leftPeak: Float, rightPeak: Float, leftRMS: Float, rightRMS: Float) {
        audioLevels = DiagnosticReport.AudioLevelInfo(
            leftPeak: leftPeak,
            rightPeak: rightPeak,
            leftRMS: leftRMS,
            rightRMS: rightRMS
        )
    }

    func setArtifactMonitor(_ monitor: AudioArtifactMonitor) {
        artifactMonitor = monitor
    }

    func addLogEntry(category: String, level: LogLevel, message: String) {
        additionalEntries.append((category, level, message))
    }

    func build() -> DiagnosticReport {
        let systemInfo = gatherSystemInfo()
        let artifactInfo = gatherArtifactInfo()
        let logEntries = gatherLogEntries()
        let performanceInfo = gatherPerformanceInfo()

        return DiagnosticReport(
            timestamp: Date(),
            sessionId: sessionId,
            systemInfo: systemInfo,
            playbackState: playbackState ?? DiagnosticReport.PlaybackStateInfo(
                state: "unknown", currentFile: nil, format: nil,
                sampleRate: nil, channelCount: nil, bitDepth: nil,
                durationSeconds: nil, currentPositionSeconds: nil
            ),
            audioLevels: audioLevels ?? DiagnosticReport.AudioLevelInfo(
                leftPeak: 0, rightPeak: 0, leftRMS: 0, rightRMS: 0
            ),
            artifacts: artifactInfo,
            logEntries: logEntries,
            performance: performanceInfo
        )
    }

    func buildAndSave(to directory: URL? = nil) -> URL? {
        let report = build()
        guard let data = report.toJSONData() else { return nil }

        let saveDir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AudioPlayerMac")
            .appendingPathComponent("reports") ?? FileManager.default.temporaryDirectory

        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "diagnostic-\(timestamp).json"
        let fileURL = saveDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: .atomic)
            PlayerLogger.shared.log(category: "diagnostic", message: "Report saved to \(fileURL.path)")
            return fileURL
        } catch {
            PlayerLogger.shared.log(category: "diagnostic", level: .error, message: "Failed to save report: \(error)")
            return nil
        }
    }

    // MARK: - Private

    private func gatherSystemInfo() -> DiagnosticReport.SystemInfo {
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion
        let macOSVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let hardwareModel = String(cString: model)

        let cpuCount = processInfo.processorCount
        let totalMemoryMB = Int(processInfo.physicalMemory / 1_048_576)

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        return DiagnosticReport.SystemInfo(
            macOSVersion: macOSVersion,
            hardwareModel: hardwareModel,
            cpuCount: cpuCount,
            totalMemoryMB: totalMemoryMB,
            appVersion: appVersion
        )
    }

    private func gatherArtifactInfo() -> DiagnosticReport.ArtifactInfo {
        guard let monitor = artifactMonitor else {
            return DiagnosticReport.ArtifactInfo(
                totalArtifacts: 0,
                artifactsByType: [:],
                recentEvents: []
            )
        }

        let recentEvents = monitor.getRecentEvents(limit: 50).map {
            DiagnosticReport.ArtifactEventInfo(
                type: $0.type.rawValue,
                severity: $0.severity.rawValue,
                magnitude: $0.magnitude,
                positionMs: $0.positionMs,
                timestamp: ISO8601DateFormatter().string(from: $0.timestamp)
            )
        }

        return DiagnosticReport.ArtifactInfo(
            totalArtifacts: monitor.getArtifactCountTotal(),
            artifactsByType: monitor.getArtifactCountByType(),
            recentEvents: recentEvents
        )
    }

    private func gatherLogEntries() -> [DiagnosticReport.LogEntryInfo] {
        let entries = PlayerLogger.shared.getEntries(limit: 200)
        return entries.map {
            DiagnosticReport.LogEntryInfo(
                timestamp: ISO8601DateFormatter().string(from: $0.timestamp),
                level: $0.level.rawValue,
                category: $0.category,
                message: $0.message
            )
        }
    }

    private func gatherPerformanceInfo() -> DiagnosticReport.PerformanceInfo {
        var memoryUsageMB: Double = 0
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryUsageMB = Double(info.resident_size) / 1_048_576
        }

        return DiagnosticReport.PerformanceInfo(
            memoryUsageMB: memoryUsageMB,
            cpuUsagePercent: 0,
            bufferUnderruns: 0,
            averageDecodeTimeMs: 0
        )
    }
}
