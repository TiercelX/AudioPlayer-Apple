import Foundation
import AVFoundation

class VolumeController {
    private var volume: Float = 1.0
    private var isFading = false
    private var fadeTimer: Timer?
    private var fadeStartTime: Date?
    private var fadeDuration: TimeInterval = 0
    private var fadeStartVolume: Float = 0
    private var fadeTargetVolume: Float = 0
    
    var currentVolume: Float {
        return volume
    }
    
    func setVolume(_ newVolume: Float) {
        let clampedVolume = max(0, min(1, newVolume))
        volume = clampedVolume
    }
    
    func fadeOut(duration: TimeInterval, completion: @escaping () -> Void) {
        guard !isFading else { return }
        
        isFading = true
        fadeStartTime = Date()
        fadeDuration = duration
        fadeStartVolume = volume
        fadeTargetVolume = 0
        
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(self.fadeStartTime ?? Date())
            let progress = min(elapsed / self.fadeDuration, 1.0)
            
            let newVolume = self.fadeStartVolume + (self.fadeTargetVolume - self.fadeStartVolume) * Float(progress)
            self.volume = newVolume
            
            if progress >= 1.0 {
                timer.invalidate()
                self.isFading = false
                self.volume = self.fadeTargetVolume
                completion()
            }
        }
    }
    
    func fadeIn(duration: TimeInterval, from startVolume: Float = 0, to targetVolume: Float = 1.0, completion: @escaping () -> Void) {
        guard !isFading else { return }
        
        isFading = true
        fadeStartTime = Date()
        fadeDuration = duration
        fadeStartVolume = startVolume
        fadeTargetVolume = targetVolume
        volume = startVolume
        
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(self.fadeStartTime ?? Date())
            let progress = min(elapsed / self.fadeDuration, 1.0)
            
            let newVolume = self.fadeStartVolume + (self.fadeTargetVolume - self.fadeStartVolume) * Float(progress)
            self.volume = newVolume
            
            if progress >= 1.0 {
                timer.invalidate()
                self.isFading = false
                self.volume = self.fadeTargetVolume
                completion()
            }
        }
    }
    
    func stopFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        isFading = false
    }
    
    func mute() {
        volume = 0
    }
    
    func unmute(to previousVolume: Float = 1.0) {
        volume = previousVolume
    }
}