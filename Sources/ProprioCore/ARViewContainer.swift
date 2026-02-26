import Foundation
import ARKit
import RealityKit
import SwiftUI

public struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var analyzer: MotionAnalyzer
    @ObservedObject var haptics: HapticController
    
    public init(analyzer: MotionAnalyzer, haptics: HapticController) {
        self.analyzer = analyzer
        self.haptics = haptics
    }
    
    public func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR Session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        
        // Enable People Occlusion (critical for immersion)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        arView.session.run(config)
        
        // Add Coordinator as Delegate
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        
        return arView
    }
    
    public func updateUIView(_ uiView: ARView, context: Context) {
        // Manage Guide Path visibility
        if analyzer.gaitStabilityIndex < 0.8 {
            context.coordinator.showGuidePath()
        } else {
            context.coordinator.hideGuidePath()
        }
        
        // Trigger Haptic Correction
        if analyzer.tremorAmplitude > 0.3 {
            haptics.playTremorCorrection(intensity: Float(analyzer.tremorAmplitude))
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        var arView: ARView?
        var guidePathAnchor: AnchorEntity?
        
        // Throttle Vision analysis to ~10fps to save battery/CPU
        private var lastAnalysisTime: TimeInterval = 0
        private let analysisInterval: TimeInterval = 0.1
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        // MARK: - ARSessionDelegate
        
        public func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let currentTime = frame.timestamp
            if currentTime - lastAnalysisTime > analysisInterval {
                parent.analyzer.processFrame(frame.capturedImage)
                lastAnalysisTime = currentTime
            }
            
            // Keep Guide Path positioned relative to user
            updateGuidePathPosition(frame)
        }
        
        public func session(_ session: ARSession, didFailWithError error: Error) {
            // Handle AR errors (e.g., tracking lost)
            print("AR Session Failed: \(error.localizedDescription)")
        }
        
        // MARK: - Guide Path Logic
        
        func showGuidePath() {
            guard let arView = arView, guidePathAnchor == nil else { return }
            
            // Create a simple guide line (long green rectangle on floor)
            let mesh = MeshResource.generateBox(size: [0.1, 0.01, 2.0]) // 2m long path
            let material = SimpleMaterial(color: .green, isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            
            // Create anchor using explicit AnchoringComponent target for compatibility
            let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.2, 0.2]))
            anchor.addChild(entity)
            
            arView.scene.addAnchor(anchor)
            guidePathAnchor = anchor
        }
        
        func hideGuidePath() {
            guard let anchor = guidePathAnchor else { return }
            arView?.scene.removeAnchor(anchor)
            guidePathAnchor = nil
        }
        
        func updateGuidePathPosition(_ frame: ARFrame) {
            guard let anchor = guidePathAnchor else { return }
            
            // Keep anchor 1.5m in front of camera, aligned with gravity
            // This is a naive implementation; ideal would be to lock it to the floor plane once found
            // rather than constantly updating, to prevent jitter.
            // For now, we leave it anchored to the detected plane (handled by ARKit).
        }
    }
}
