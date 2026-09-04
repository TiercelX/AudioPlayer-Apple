import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var sliderValue: Double = 0
    @State private var isSeeking = false
    @State private var showMediaInfo = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Spacer()
            nowPlayingSection
            Spacer()
            progressSection
            PlayerControlsView()
                .padding(.bottom, 16)
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(KeyboardShortcutsModifier(appState: appState))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private var headerBar: some View {
        HStack {
            Button(action: { appState.openFile() }) {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                Text("Open")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white)
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor)
            .cornerRadius(6)

            Spacer()

            if let url = appState.currentFile {
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 300)

                Button(action: { showMediaInfo.toggle() }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showMediaInfo, arrowEdge: .bottom) {
                    MediaInfoView(mediaInfo: appState.currentMediaInfo, outputInfo: appState.currentOutputInfo)
                }
            }

            Spacer()

            Toggle("精确播放", isOn: $appState.precisePlayback)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help("Match output device sample rate to source file")
                .onChange(of: appState.precisePlayback) { enabled in
                    if enabled, let info = appState.currentMediaInfo, info.sampleRate > 0 {
                        appState.outputDeviceManager?.setOutputSampleRate(info.sampleRate)
                    }
                    appState.updateOutputInfo()
                }

            volumeControl
            outputDeviceMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var volumeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Slider(value: $appState.volume, in: 0...1)
                .frame(width: 100)
                .onChange(of: appState.volume) { newValue in
                    appState.setVolume(newValue)
                }
        }
    }

    private var outputDeviceMenu: some View {
        Menu {
            Button("System Default") {
                appState.outputDeviceManager?.selectDefaultDevice()
            }
            
            if !appState.availableOutputDevices.isEmpty {
                Divider()
                
                ForEach(appState.availableOutputDevices, id: \.id) { device in
                    Button(action: {
                        appState.selectOutputDevice(device)
                    }) {
                        HStack {
                            Text(device.name)
                            
                            if device.id == appState.selectedOutputDevice?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
    }

    private var nowPlayingSection: some View {
        VStack(spacing: 12) {
            albumArtPlaceholder
            if let url = appState.currentFile {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            } else {
                Text("No file loaded")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Text(appState.playbackStatus)
                .font(.system(size: 12))
                .foregroundColor(appState.playbackStatus.lowercased().contains("unsupported") ? .red : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private var albumArtPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 180, height: 180)

            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: $sliderValue,
                in: 0...max(appState.duration, 0.01),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        appState.seek(to: sliderValue)
                    }
                }
            )
            .disabled(appState.duration == 0)
            .onChange(of: appState.currentTime) { newTime in
                if !isSeeking {
                    sliderValue = newTime
                }
            }

            HStack {
                Text(formatTime(appState.currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(appState.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "00:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: "public.file-url") { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            
            DispatchQueue.main.async {
                appState.loadFile(url: url)
            }
        }
        
        return true
    }
}

struct KeyboardShortcutsModifier: ViewModifier {
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.space) {
                    if appState.isPlaying { appState.pause() } else { appState.play() }
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    appState.seek(to: max(appState.currentTime - 5, 0))
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    appState.seek(to: min(appState.currentTime + 5, appState.duration))
                    return .handled
                }
        } else {
            content
        }
    }
}

struct MainWindow_Previews: PreviewProvider {
    static var previews: some View {
        MainWindow()
            .environmentObject(AppState())
    }
}
