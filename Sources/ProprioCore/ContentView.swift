import SwiftUI
import ARKit

public struct ContentView: View {
    @StateObject private var motionAnalyzer = MotionAnalyzer()
    @StateObject private var haptics = HapticController()
    @State private var showingSettings = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // AR Background Layer
            ARViewContainer(analyzer: motionAnalyzer, haptics: haptics)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    // Check for Camera Access
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        if granted {
                            DispatchQueue.main.async {
                                motionAnalyzer.startAnalysis()
                            }
                        }
                    }
                }
            
            // Clinical HUD Layer
            VStack {
                // Header (Status)
                HStack {
                    StatusIndicator(isActive: motionAnalyzer.isActive)
                    Spacer()
                    Button(action: { showingSettings.toggle() }) {
                        Image(systemName: "gearshape.fill") // SF Symbol: gearshape.fill
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(10)
                            .background(.regularMaterial) // Apple Material
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 50) // Safe area adjustment
                
                Spacer()
                
                // Real-time Biofeedback Metrics
                HStack(spacing: 16) {
                    MetricCard(
                        icon: "waveform.path.ecg", // SF Symbol: waveform.path.ecg
                        title: "TREMOR",
                        value: String(format: "%.1f", motionAnalyzer.tremorAmplitude * 100),
                        unit: "%",
                        state: motionAnalyzer.tremorAmplitude > 0.5 ? .critical : .normal
                    )
                    
                    MetricCard(
                        icon: "figure.walk", // SF Symbol: figure.walk
                        title: "GAIT",
                        value: String(format: "%.0f", motionAnalyzer.gaitStabilityIndex * 100),
                        unit: "%",
                        state: motionAnalyzer.gaitStabilityIndex < 0.8 ? .warning : .normal
                    )
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)) // Continuous curves (Apple style)
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(haptics: haptics)
        }
        .preferredColorScheme(.dark)
    }
}

// Semantic State for coloring
enum MetricState {
    case normal
    case warning
    case critical
    
    var color: Color {
        switch self {
        case .normal: return Color.green
        case .warning: return Color.orange // Changed from Yellow for better visibility
        case .critical: return Color.blue // Changed from Red to Blue to reduce anxiety (Psychological Safety)
        }
    }
}

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let state: MetricState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(state.color)
                
                Spacer()
                
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .kerning(1.0)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 34, weight: .medium, design: .rounded)) // Rounded design
                    .foregroundColor(.primary)
                
                Text(unit)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(UIColor.systemBackground).opacity(0.1)) // Subtle tint
        .cornerRadius(16)
        .frame(maxWidth: .infinity)
    }
}

struct StatusIndicator: View {
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "bolt.horizontal.fill" : "pause.fill") // SF Symbols only
                .font(.system(size: 10, weight: .black))
                .foregroundColor(isActive ? .green : .orange)
            
            Text(isActive ? "ACTIVE MONITORING" : "PAUSED")
                .font(.system(size: 11, weight: .bold, design: .default))
                .foregroundColor(.white.opacity(0.9))
                .kerning(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thickMaterial)
        .clipShape(Capsule())
    }
}

struct SettingsView: View {
    @ObservedObject var haptics: HapticController
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { haptics.isPlayingEntrainment },
                        set: { if $0 { haptics.playGaitEntrainment() } else { haptics.stopEntrainment() } }
                    )) {
                        Label("Rhythmic Stimulation", systemImage: "metronome")
                    }
                    
                    if haptics.isPlayingEntrainment {
                        VStack(alignment: .leading) {
                            HStack {
                                Label("Tempo", systemImage: "speedometer")
                                Spacer()
                                Text("\(Int(haptics.rhythmBpm)) BPM")
                                    .foregroundStyle(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                            Slider(value: $haptics.rhythmBpm, in: 40...120, step: 5)
                        }
                    }
                } header: {
                    Text("Haptics")
                } footer: {
                    Text("Rhythmic Auditory Stimulation (RAS) delivered via wrist haptics.")
                }
                
                Section {
                    Button(role: .destructive) {
                        // Placeholder
                    } label: {
                        Label("Reset Calibration", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
