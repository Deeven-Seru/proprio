import CoreHaptics
import Foundation
import UIKit

public enum HapticError: Error, LocalizedError {
    case engineNotSupported
    case patternFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .engineNotSupported: return "Haptics not supported on this device."
        case .patternFailed(let error): return "Failed to play haptic pattern: \(error.localizedDescription)"
        }
    }
}

/// Manages haptic feedback delivery using CoreHaptics.
///
/// Implements Rhythmic Auditory Stimulation (RAS) concepts via tactile pulses.
public class HapticController: ObservableObject {
    private var engine: CHHapticEngine?
    private var timer: Timer?
    
    private let minHapticIntensity: Float = 0.1
    
    // Published properties for UI/Status
    @Published public var isPlayingEntrainment: Bool = false
    @Published public var lastError: HapticError?
    
    // Configurable parameters
    @Published public var rhythmBpm: Double = 60.0 { // Base metronome (steps per minute)
        didSet {
            // Restart timer with new BPM if entrainment is active
            if isPlayingEntrainment {
                timer?.invalidate()
                let interval = 60.0 / rhythmBpm
                let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                    self?.playSharpTick()
                }
                RunLoop.main.add(newTimer, forMode: .common)
                timer = newTimer
            }
        }
    }
    
    @Published public var hapticIntensity: Float = 1.0 // User-adjustable intensity (0.0–1.0)
    
    public init() {
        prepareHaptics()
    }
    
    deinit {
        stopEntrainment()
        engine?.stop(completionHandler: nil)
    }
    
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            lastError = .engineNotSupported
            return
        }
        
        do {
            engine = try CHHapticEngine()
            
            // Handle engine reset (e.g. background/foreground transitions)
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            
            // Handle engine stop (e.g. audio session interruption)
            engine?.stoppedHandler = { [weak self] reason in
                print("Haptic engine stopped: \(reason.rawValue)")
                DispatchQueue.main.async {
                    self?.isPlayingEntrainment = false
                }
            }
            
            // Start immediately
            try engine?.start()
        } catch {
            lastError = .patternFailed(error)
        }
    }
    
    /// Starts the rhythmic metronome for gait stabilization.
    public func playGaitEntrainment() {
        guard !isPlayingEntrainment else { return }
        
        let interval = 60.0 / rhythmBpm
        
        // Start Timer on main RunLoop for consistency
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.playSharpTick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        
        isPlayingEntrainment = true
    }
    
    /// Stops the rhythmic metronome.
    public func stopEntrainment() {
        timer?.invalidate()
        timer = nil
        isPlayingEntrainment = false
    }
    
    /// Stops all haptic activity immediately (emergency stop).
    public func emergencyStop() {
        stopEntrainment()
        engine?.stop(completionHandler: nil)
        // Re-prepare for future use
        prepareHaptics()
    }
    
    /// Delivers a single, sharp transient haptic event (Tick).
    private func playSharpTick() {
        guard let engine = engine else { return }
        
        // Scale intensity by user preference
        let scaledIntensity = max(minHapticIntensity, hapticIntensity)
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: scaledIntensity)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play tick: \(error)")
        }
    }
    
    /// Provides continuous feedback proportional to tremor intensity.
    /// - Parameter intensity: Normalized intensity (0.0 to 1.0).
    public func playTremorCorrection(intensity: Float) {
        guard let engine = engine, intensity > minHapticIntensity else { return }
        
        // Scale by user preference
        let scaledIntensity = intensity * hapticIntensity
        
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: scaledIntensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3) // Dull/heavy feel
        
        // Use a continuous event for smooth feedback
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensityParam, sharpnessParam], relativeTime: 0, duration: 0.15)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play continuous feedback: \(error)")
        }
    }
}
