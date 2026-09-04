import SwiftUI

@main
struct AudioPlayerMacApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appState.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Divider()
                
                Button("Play/Pause") {
                    if appState.isPlaying {
                        appState.pause()
                    } else {
                        appState.play()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Button("Stop") {
                    appState.stop()
                }
                .keyboardShortcut(".", modifiers: .command)
                
                Button("Skip Forward 10s") {
                    let newTime = min(appState.currentTime + 10, appState.duration)
                    appState.seek(to: newTime)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                
                Button("Skip Back 10s") {
                    let newTime = max(appState.currentTime - 10, 0)
                    appState.seek(to: newTime)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
    }
}
