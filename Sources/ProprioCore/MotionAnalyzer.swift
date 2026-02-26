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

/// Operating mode for the analyzer
public enum AnalysisMode: String, CaseIterable {
    case gait = "Gait Assistance"
    case tremor = "Fine Motor"
}

/// Analyzes body pose from video frames to detect tremor and gait anomalies.
public class MotionAnalyzer: ObservableObject {
    // Published properties for UI updates
    @Published public var tremorAmplitude: Double = 0.0
    @Published public var gaitStabilityIndex: Double = 1.0 // 1.0 = stable, < 0.8 = unstable
    @Published public var isActive: Bool = false
    @Published public var lastError: MotionAnalysisError?
    @Published public var currentMode: AnalysisMode = .gait
    @Published public var tremorTrend: TremorTrend = .stable
    @Published public var gaitSymmetryIndex: Double = 1.0 // 1.0 = perfect symmetry
    @Published public var sessionStepCount: Int = 0
    
    /// Indicates the direction of tremor change over time
    public enum TremorTrend: String {
        case increasing = "↑"
        case decreasing = "↓"
        case stable = "→"
    }
    
    // Vision request for pose detection
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    
    // Concurrency
    private let analysisQueue = DispatchQueue(label: "com.proprio.analysis", qos: .userInitiated)
    
    // Historical data for variance calculation (Ring buffer)
    private var rightWristPositions: [CGPoint] = []
    private var leftWristPositions: [CGPoint] = []
    private var leftAnklePositions: [CGPoint] = []
    private var rightAnklePositions: [CGPoint] = []
    private let maxHistorySize = 60 // ~1 second at 60fps
    
    // Trend tracking
    private var recentAmplitudes: [Double] = []
    private let trendWindowSize = 30
    private let minTrendSamples = 10
    private let trendThreshold = 0.02
    
    // Gait step detection
    private var lastStepTime: TimeInterval = 0
    private var stepIntervals: [Double] = []
    
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
    
    /// Resets all accumulated metrics for a fresh session.
    public func resetMetrics() {
        DispatchQueue.main.async {
            self.tremorAmplitude = 0.0
            self.gaitStabilityIndex = 1.0
            self.gaitSymmetryIndex = 1.0
            self.sessionStepCount = 0
            self.tremorTrend = .stable
            self.lastError = nil
        }
        rightWristPositions.removeAll()
        leftWristPositions.removeAll()
        leftAnklePositions.removeAll()
        rightAnklePositions.removeAll()
        recentAmplitudes.removeAll()
        stepIntervals.removeAll()
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
                
                switch self.currentMode {
                case .tremor:
                    self.processTremorMode(observation)
                case .gait:
                    self.processGaitMode(observation)
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.lastError = .visionRequestFailed(error)
                }
            }
        }
    }
    
    // MARK: - Tremor Mode (Bilateral Wrist Tracking)
    
    private func processTremorMode(_ observation: VNHumanBodyPoseObservation) {
        do {
            let rightWrist = try observation.recognizedPoint(.rightWrist)
            let leftWrist = try observation.recognizedPoint(.leftWrist)
            
            if rightWrist.confidence > 0.3 {
                let point = CGPoint(x: rightWrist.location.x, y: rightWrist.location.y)
                rightWristPositions.append(point)
                if rightWristPositions.count > maxHistorySize {
                    rightWristPositions.removeFirst()
                }
            }
            
            if leftWrist.confidence > 0.3 {
                let point = CGPoint(x: leftWrist.location.x, y: leftWrist.location.y)
                leftWristPositions.append(point)
                if leftWristPositions.count > maxHistorySize {
                    leftWristPositions.removeFirst()
                }
            }
            
            // Average bilateral tremor for more robust measurement
            let rightVariance = computeVariance(rightWristPositions)
            let leftVariance = computeVariance(leftWristPositions)
            let avgVariance = (rightVariance + leftVariance) / 2.0
            
            updateTremorMetricsFromVariance(avgVariance)
        } catch {
            // Individual keypoint extraction failed — non-fatal
        }
    }
    
    // MARK: - Gait Mode (Ankle + Hip Tracking)
    
    private func processGaitMode(_ observation: VNHumanBodyPoseObservation) {
        do {
            let leftAnkle = try observation.recognizedPoint(.leftAnkle)
            let rightAnkle = try observation.recognizedPoint(.rightAnkle)
            
            if leftAnkle.confidence > 0.3 {
                let point = CGPoint(x: leftAnkle.location.x, y: leftAnkle.location.y)
                leftAnklePositions.append(point)
                if leftAnklePositions.count > maxHistorySize {
                    leftAnklePositions.removeFirst()
                }
            }
            
            if rightAnkle.confidence > 0.3 {
                let point = CGPoint(x: rightAnkle.location.x, y: rightAnkle.location.y)
                rightAnklePositions.append(point)
                if rightAnklePositions.count > maxHistorySize {
                    rightAnklePositions.removeFirst()
                }
            }
            
            // Compute gait symmetry from left/right ankle variance ratio
            let leftVar = computeVariance(leftAnklePositions)
            let rightVar = computeVariance(rightAnklePositions)
            let maxVar = max(leftVar, rightVar, 0.001)
            let minVar = max(min(leftVar, rightVar), 0.001)
            let symmetry = minVar / maxVar // 1.0 = perfect symmetry
            
            // Also track wrists for tremor as secondary metric
            let rightWrist = try observation.recognizedPoint(.rightWrist)
            if rightWrist.confidence > 0.3 {
                let point = CGPoint(x: rightWrist.location.x, y: rightWrist.location.y)
                rightWristPositions.append(point)
                if rightWristPositions.count > maxHistorySize {
                    rightWristPositions.removeFirst()
                }
            }
            
            let wristVariance = computeVariance(rightWristPositions)
            updateTremorMetricsFromVariance(wristVariance)
            
            DispatchQueue.main.async {
                // EMA for stability
                let alpha = 0.2
                self.gaitSymmetryIndex = (symmetry * alpha) + (self.gaitSymmetryIndex * (1.0 - alpha))
            }
        } catch {
            // Individual keypoint extraction failed — non-fatal
        }
    }
    
    // MARK: - Shared Computations
    
    private func computeVariance(_ positions: [CGPoint]) -> Double {
        guard positions.count > 1 else { return 0.0 }
        
        let xValues = positions.map { $0.x }
        let yValues = positions.map { $0.y }
        
        let meanX = xValues.reduce(0, +) / Double(xValues.count)
        let meanY = yValues.reduce(0, +) / Double(yValues.count)
        
        let varianceX = xValues.map { Foundation.pow($0 - meanX, 2) }.reduce(0, +) / Double(xValues.count)
        let varianceY = yValues.map { Foundation.pow($0 - meanY, 2) }.reduce(0, +) / Double(yValues.count)
        
        return sqrt(varianceX + varianceY)
    }
    
    private func updateTremorMetricsFromVariance(_ totalVariance: Double) {
        // Normalize for UI (heuristic scaling)
        let rawAmplitude = min(totalVariance * 500, 1.0)
        
        // Apply Exponential Moving Average (EMA) for clinical smoothness
        let alpha = 0.2
        let smoothedAmplitude = (rawAmplitude * alpha) + (self.tremorAmplitude * (1.0 - alpha))
        
        // Gait stability inversely correlates with tremor
        let simulatedStability = max(1.0 - (smoothedAmplitude * 0.5), 0.0)
        
        // Track trend
        recentAmplitudes.append(smoothedAmplitude)
        if recentAmplitudes.count > trendWindowSize {
            recentAmplitudes.removeFirst()
        }
        
        let trend: TremorTrend
        if recentAmplitudes.count >= minTrendSamples {
            let firstHalf = Array(recentAmplitudes.prefix(recentAmplitudes.count / 2))
            let secondHalf = Array(recentAmplitudes.suffix(recentAmplitudes.count / 2))
            let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
            let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
            let diff = secondAvg - firstAvg
            if diff > trendThreshold {
                trend = .increasing
            } else if diff < -trendThreshold {
                trend = .decreasing
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }
        
        DispatchQueue.main.async {
            self.tremorAmplitude = smoothedAmplitude
            self.gaitStabilityIndex = simulatedStability
            self.tremorTrend = trend
        }
    }
}
