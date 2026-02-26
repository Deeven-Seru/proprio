import Foundation
import Vision
import ARKit
import Combine

/// Errors that can occur during motion analysis
public enum MotionAnalysisError: Error, LocalizedError {
    case cameraUnavailable
    case visionRequestFailed(Error)
    case lowConfidence
    
    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "Camera access is required for motion analysis."
        case .visionRequestFailed(let error): return "Vision request failed: \(error.localizedDescription)"
        case .lowConfidence: return "Tracking confidence too low. Please ensure good lighting and visibility."
        }
    }
}

/// Analyzes body pose from video frames to detect tremor and gait anomalies.
public class MotionAnalyzer: ObservableObject {
    // Published properties for UI updates
    @Published public var tremorAmplitude: Double = 0.0
    @Published public var gaitStabilityIndex: Double = 1.0 // 1.0 = stable, < 0.8 = unstable
    @Published public var isActive: Bool = false
    @Published public var lastError: MotionAnalysisError?
    
    // Vision request for pose detection
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    
    // Concurrency
    private let analysisQueue = DispatchQueue(label: "com.proprio.analysis", qos: .userInitiated)
    
    // Historical data for variance calculation (Ring buffer)
    private var wristPositions: [CGPoint] = []
    private let maxHistorySize = 60 // ~1 second at 60fps
    
    public init() {
        // Configure Vision request
        poseRequest.usesCPUOnly = false // Use Neural Engine where possible
    }
    
    public func startAnalysis() {
        DispatchQueue.main.async {
            self.isActive = true
            self.lastError = nil
        }
    }
    
    public func stopAnalysis() {
        DispatchQueue.main.async {
            self.isActive = false
        }
    }
    
    /// Processes a single video frame for body pose analysis.
    /// - Parameter pixelBuffer: The video frame buffer.
    public func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isActive else { return }
        
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
            do {
                try handler.perform([self.poseRequest])
                
                guard let observation = self.poseRequest.results?.first else { return }
                
                // Extract keypoints (Right Wrist for tremor demo)
                let rightWrist = try observation.recognizedPoint(.rightWrist)
                
                if rightWrist.confidence > 0.3 {
                    // Normalize coordinates and store
                    let point = CGPoint(x: rightWrist.location.x, y: rightWrist.location.y)
                    self.updateTremorMetrics(point)
                } else {
                    // Optional: Report low confidence if persistent, but avoid spamming UI
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.lastError = .visionRequestFailed(error)
                }
            }
        }
    }
    
    private func updateTremorMetrics(_ point: CGPoint) {
        wristPositions.append(point)
        if wristPositions.count > maxHistorySize {
            wristPositions.removeFirst()
        }
        
        // Calculate variance (Tremor Amplitude)
        // We look at the magnitude of deviation from the moving average
        
        let xValues = wristPositions.map { $0.x }
        let yValues = wristPositions.map { $0.y }
        
        let meanX = xValues.reduce(0, +) / Double(xValues.count)
        let meanY = yValues.reduce(0, +) / Double(yValues.count)
        
        // Use Foundation.pow for explicit Double calculation to avoid CoreGraphics ambiguity
        let varianceX = xValues.map { Foundation.pow($0 - meanX, 2) }.reduce(0, +) / Double(xValues.count)
        let varianceY = yValues.map { Foundation.pow($0 - meanY, 2) }.reduce(0, +) / Double(yValues.count)
        
        let totalVariance = sqrt(varianceX + varianceY)
        
        // Normalize for UI (heuristic scaling)
        let rawAmplitude = min(totalVariance * 500, 1.0)
        
        // Apply Exponential Moving Average (EMA) for clinical smoothness
        // Alpha of 0.2 means we value new data at 20% and history at 80%
        // This prevents the numbers from jittering wildly
        let alpha = 0.2
        let smoothedAmplitude = (rawAmplitude * alpha) + (self.tremorAmplitude * (1.0 - alpha))
        
        // Gait Stability simulation (in real app, this would analyze leg keypoints)
        // For demo, we inversely correlate with tremor
        let simulatedStability = max(1.0 - (smoothedAmplitude * 0.5), 0.0)
        
        DispatchQueue.main.async {
            self.tremorAmplitude = smoothedAmplitude
            self.gaitStabilityIndex = simulatedStability
        }
    }
}
