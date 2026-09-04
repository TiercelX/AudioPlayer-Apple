import SwiftUI

struct MediaInfoView: View {
    let mediaInfo: MediaInfo?
    let outputInfo: OutputFormatInfo?

    var body: some View {
        if let info = mediaInfo {
            VStack(alignment: .leading, spacing: 12) {
                headerRow(info)
                Divider()
                sectionLabel("Source")
                sourceGrid(info)
                if let output = outputInfo {
                    Divider()
                    sectionLabel("Output")
                    outputGrid(output)
                }
            }
            .padding(16)
            .frame(width: 340)
        } else {
            Text("No media info available")
                .foregroundColor(.secondary)
                .padding(20)
        }
    }

    // MARK: - Header

    private func headerRow(_ info: MediaInfo) -> some View {
        HStack {
            Text(info.fileName)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Spacer()
            if info.isDolby {
                badge("Dolby", color: .blue)
            }
            if info.isLossless {
                badge("Lossless", color: .green)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    // MARK: - Sections

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private func sourceGrid(_ info: MediaInfo) -> some View {
        VStack(spacing: 5) {
            row("Format", info.codecName)
            row("Sample Rate", info.sampleRateFormatted)
            row("Channels", "\(info.channelCount)")
            row("Bit Depth", info.bitDepthFormatted)
            if info.bitrate > 0 {
                row("Bitrate", info.bitrateFormatted)
            }
            row("Duration", info.durationFormatted)
            row("File Size", info.fileSizeFormatted)
            row("Extension", info.fileExtension.uppercased())
        }
    }

    private func outputGrid(_ output: OutputFormatInfo) -> some View {
        VStack(spacing: 5) {
            row("Device", output.deviceName)
            row("Sample Rate", output.sampleRateFormatted)
            row("Channels", "\(output.channelCount)")
            row("Bit Depth", output.bitDepthFormatted)
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }
}
