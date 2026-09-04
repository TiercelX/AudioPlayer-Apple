import SwiftUI

struct PlayerControlsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 24) {
            stopButton
            playPauseButton
            skipForwardButton
        }
        .padding(.vertical, 8)
    }

    private var playPauseButton: some View {
        Button(action: {
            if appState.isPlaying {
                appState.pause()
            } else {
                appState.play()
            }
        }) {
            Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 28, weight: .medium))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(Color.accentColor)
        )
        .foregroundColor(.white)
        .disabled(appState.currentFile == nil)
        .opacity(appState.currentFile == nil ? 0.5 : 1.0)
    }

    private var stopButton: some View {
        Button(action: {
            appState.stop()
        }) {
            Image(systemName: "stop.fill")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(Color.gray.opacity(0.2))
        )
        .foregroundColor(.primary)
        .disabled(appState.currentFile == nil || !appState.isActive)
        .opacity(appState.currentFile == nil || !appState.isActive ? 0.5 : 1.0)
    }

    private var skipForwardButton: some View {
        Button(action: {
            let newTime = min(appState.currentTime + 10, appState.duration)
            appState.seek(to: newTime)
        }) {
            Image(systemName: "goforward.10")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(Color.gray.opacity(0.2))
        )
        .foregroundColor(.primary)
        .disabled(appState.currentFile == nil)
        .opacity(appState.currentFile == nil ? 0.5 : 1.0)
    }
}

struct PlayerControlsView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerControlsView()
            .environmentObject(AppState())
    }
}
