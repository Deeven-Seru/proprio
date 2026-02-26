import SwiftUI
import ARKit

// MARK: - App Mode

enum AppMode: String, CaseIterable, Hashable {
    case gait = "Gait Assistance"
    case fineMotor = "Fine Motor"

    var icon: String {
        switch self {
        case .gait: return "figure.walk"
        case .fineMotor: return "hand.raised.fingers.spread"
        }
    }
}

// MARK: - Trend Direction

enum TrendDirection {
    case increasing, decreasing, stable

    var symbol: String {
        switch self {
        case .increasing: return "↑"
        case .decreasing: return "↓"
        case .stable: return "→"
        }
    }

    var label: String {
        switch self {
        case .increasing: return "increasing"
        case .decreasing: return "decreasing"
        case .stable: return "stable"
        }
    }
}

// MARK: - Semantic State (Psychological Safety palette)

enum MetricState {
    case normal   // Green
    case warning  // Orange (not yellow — better visibility)
    case critical // Blue (not red — reduces anxiety)

    var color: Color {
        switch self {
        case .normal: return Color.green
        case .warning: return Color.orange
        case .critical: return Color.blue
        }
    }
}

// MARK: - ContentView

public struct ContentView: View {
    @StateObject private var motionAnalyzer = MotionAnalyzer()
    @StateObject private var haptics = HapticController()

    @State private var showingSettings = false
    @State private var selectedMode: AppMode = .gait
    @State private var emergencyStopped = false

    // Session timer
    @State private var sessionStartDate: Date? = nil
    @State private var sessionElapsed: TimeInterval = 0
    private let sessionTimerPublisher = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Trend tracking
    @State private var previousGait: Double = 1.0
    @State private var gaitTrend: TrendDirection = .stable

    // Onboarding
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    // Camera permission
    @State private var cameraAuthorized: Bool? = nil

    public init() {}

    public var body: some View {
        ZStack {
            // AR Background Layer
            ARViewContainer(analyzer: motionAnalyzer, haptics: haptics)
                .edgesIgnoringSafeArea(.all)
                .accessibilityHidden(true)
                .onAppear {
                    checkCameraAndStart()
                    if !hasCompletedOnboarding {
                        showOnboarding = true
                    }
                }

            // Clinical HUD Layer
            VStack(spacing: 0) {
                // Header
                HStack {
                    StatusIndicator(isActive: motionAnalyzer.isActive && !emergencyStopped)
                        .accessibilityLabel(
                            motionAnalyzer.isActive && !emergencyStopped
                            ? "Status: Active monitoring" : "Status: Paused"
                        )

                    Spacer()

                    Button { showingSettings.toggle() } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings for haptics, display, and more")
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)

                Spacer()

                // Error state (center of screen)
                errorOverlay

                Spacer()

                // Bottom panel
                VStack(spacing: 12) {
                    if motionAnalyzer.isActive && !emergencyStopped {
                        sessionTimerBadge
                    }
                    modeSelector
                    metricsPanel
                    emergencyStopButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }

            // First-time onboarding
            if showOnboarding {
                OnboardingOverlay(
                    isPresented: $showOnboarding,
                    hasCompleted: $hasCompletedOnboarding
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(haptics: haptics, selectedMode: $selectedMode)
        }
        .preferredColorScheme(.dark)
        .onReceive(sessionTimerPublisher) { _ in
            if let start = sessionStartDate, motionAnalyzer.isActive, !emergencyStopped {
                sessionElapsed = Date().timeIntervalSince(start)
            }
        }
        .onChange(of: motionAnalyzer.tremorAmplitude) { _, newValue in
            updateTrends(newTremor: newValue, newGait: motionAnalyzer.gaitStabilityIndex)
        }
        .animation(.easeInOut(duration: 0.3), value: emergencyStopped)
        .animation(.easeInOut(duration: 0.3), value: motionAnalyzer.isActive)
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        selectedMode == mode
                        ? Color.white.opacity(0.2) : Color.clear
                    )
                    .clipShape(Capsule())
                }
                .accessibilityLabel("\(mode.rawValue) mode")
                .accessibilityValue(selectedMode == mode ? "Selected" : "Not selected")
                .accessibilityHint("Double tap to switch to \(mode.rawValue) mode")
                .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.thickMaterial)
        .clipShape(Capsule())
    }

    // MARK: - Metrics Panel

    private var metricsPanel: some View {
        HStack(spacing: 16) {
            if selectedMode == .gait {
                MetricCard(
                    icon: "waveform.path.ecg",
                    title: "TREMOR",
                    value: String(format: "%.1f", motionAnalyzer.tremorAmplitude * 100),
                    unit: "%",
                    state: motionAnalyzer.tremorAmplitude > 0.5 ? .critical : .normal,
                    trend: tremorTrend,
                    animationValue: motionAnalyzer.tremorAmplitude
                )
                .accessibilityLabel("Tremor level")
                .accessibilityValue(
                    "\(String(format: "%.0f", motionAnalyzer.tremorAmplitude * 100)) percent, \(tremorTrend.label)"
                )
                .accessibilityHint("Current tremor amplitude from camera tracking")

                MetricCard(
                    icon: "figure.walk",
                    title: "GAIT",
                    value: String(format: "%.0f", motionAnalyzer.gaitStabilityIndex * 100),
                    unit: "%",
                    state: motionAnalyzer.gaitStabilityIndex < 0.8 ? .warning : .normal,
                    trend: gaitTrend,
                    animationValue: motionAnalyzer.gaitStabilityIndex,
                    higherIsBetter: true
                )
                .accessibilityLabel("Gait stability")
                .accessibilityValue(
                    "\(String(format: "%.0f", motionAnalyzer.gaitStabilityIndex * 100)) percent, \(gaitTrend.label)"
                )
                .accessibilityHint("Walking stability index. Higher is more stable.")
            } else {
                MetricCard(
                    icon: "hand.raised.fingers.spread",
                    title: "STEADINESS",
                    value: String(format: "%.0f", (1.0 - motionAnalyzer.tremorAmplitude) * 100),
                    unit: "%",
                    state: motionAnalyzer.tremorAmplitude > 0.5 ? .critical :
                           motionAnalyzer.tremorAmplitude > 0.3 ? .warning : .normal,
                    trend: tremorTrend == .increasing ? .decreasing :
                           tremorTrend == .decreasing ? .increasing : .stable,
                    animationValue: motionAnalyzer.tremorAmplitude,
                    higherIsBetter: true
                )
                .accessibilityLabel("Hand steadiness")
                .accessibilityValue(
                    "\(String(format: "%.0f", (1.0 - motionAnalyzer.tremorAmplitude) * 100)) percent"
                )
                .accessibilityHint("Hand steadiness level. Higher is better.")

                MetricCard(
                    icon: "waveform.path.ecg",
                    title: "TREMOR",
                    value: String(format: "%.2f", motionAnalyzer.tremorAmplitude),
                    unit: "g",
                    state: motionAnalyzer.tremorAmplitude > 0.5 ? .critical : .normal,
                    trend: tremorTrend,
                    animationValue: motionAnalyzer.tremorAmplitude
                )
                .accessibilityLabel("Tremor intensity")
                .accessibilityValue(
                    "\(String(format: "%.2f", motionAnalyzer.tremorAmplitude)) g, \(tremorTrend.label)"
                )
                .accessibilityHint("Fine motor tremor amplitude")
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
    }

    // MARK: - Emergency Stop

    private var emergencyStopButton: some View {
        Button(action: performEmergencyStop) {
            HStack(spacing: 8) {
                Image(systemName: emergencyStopped ? "play.fill" : "stop.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(emergencyStopped ? "RESUME" : "STOP")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(
                emergencyStopped
                ? Color.green.opacity(0.8) : Color.blue.opacity(0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityLabel(emergencyStopped ? "Resume session" : "Emergency stop")
        .accessibilityHint(
            emergencyStopped
            ? "Double tap to resume AR analysis and haptics"
            : "Double tap to immediately stop all haptics and analysis"
        )
    }

    // MARK: - Session Timer

    private var sessionTimerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.green)
            Text(formattedElapsed)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thickMaterial)
        .clipShape(Capsule())
        .accessibilityLabel("Session duration")
        .accessibilityValue(accessibleElapsed)
    }

    private var formattedElapsed: String {
        let total = Int(sessionElapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var accessibleElapsed: String {
        let mins = Int(sessionElapsed) / 60
        let secs = Int(sessionElapsed) % 60
        return mins > 0 ? "\(mins) minutes \(secs) seconds" : "\(secs) seconds"
    }

    // MARK: - Error Overlay

    @ViewBuilder
    private var errorOverlay: some View {
        if cameraAuthorized == false {
            ErrorBanner(
                icon: "camera.fill",
                title: "Camera Access Needed",
                message: "Proprio needs camera access for motion tracking. Open Settings to grant access.",
                actionLabel: "Open Settings",
                action: openAppSettings
            )
            .padding(.horizontal, 20)
        } else if let error = motionAnalyzer.lastError {
            errorBanner(for: error)
                .padding(.horizontal, 20)
        }
    }

    private func errorBanner(for error: MotionAnalysisError) -> ErrorBanner {
        switch error {
        case .cameraUnavailable:
            return ErrorBanner(
                icon: "camera.trianglebadge.exclamationmark",
                title: "Camera Unavailable",
                message: "The camera could not be started. Please close other camera apps and try again.",
                actionLabel: nil,
                action: nil
            )
        case .visionRequestFailed(_):
            return ErrorBanner(
                icon: "eye.trianglebadge.exclamationmark",
                title: "Tracking Interrupted",
                message: "Motion tracking was briefly interrupted. Keep moving normally.",
                actionLabel: nil,
                action: nil
            )
        case .lowConfidence:
            return ErrorBanner(
                icon: "figure.stand",
                title: "Can't See You Clearly",
                message: "Ensure your full body is visible and the area is well lit.",
                actionLabel: nil,
                action: nil
            )
        }
    }

    // MARK: - Actions

    private func checkCameraAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAuthorized = true
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                    if granted { startSession() }
                }
            }
        default:
            cameraAuthorized = false
        }
    }

    private func startSession() {
        motionAnalyzer.startAnalysis()
        sessionStartDate = Date()
        sessionElapsed = 0
    }

    private func performEmergencyStop() {
        if emergencyStopped {
            emergencyStopped = false
            startSession()
        } else {
            emergencyStopped = true
            motionAnalyzer.stopAnalysis()
            haptics.stopEntrainment()
        }
    }

    private func updateTrends(newTremor: Double, newGait: Double) {
        let threshold = 0.02
        let gaitDelta = newGait - previousGait
        gaitTrend = calculateTrend(delta: gaitDelta, threshold: threshold)
        previousGait = newGait
    }

    private func calculateTrend(delta: Double, threshold: Double) -> TrendDirection {
        if abs(delta) < threshold { return .stable }
        return delta > 0 ? .increasing : .decreasing
    }

    /// Maps MotionAnalyzer's tremor trend to ContentView's TrendDirection
    private var tremorTrend: TrendDirection {
        switch motionAnalyzer.tremorTrend {
        case .increasing: return .increasing
        case .decreasing: return .decreasing
        case .stable: return .stable
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let state: MetricState
    var trend: TrendDirection = .stable
    var animationValue: Double = 0
    var higherIsBetter: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(state.color)

                Spacer()

                HStack(spacing: 4) {
                    Text(trend.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(trendColor)
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .kerning(1.0)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())

                Text(unit)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(UIColor.systemBackground).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.4), value: animationValue)
    }

    private var trendColor: Color {
        switch trend {
        case .increasing: return higherIsBetter ? .green : .orange
        case .decreasing: return higherIsBetter ? .orange : .green
        case .stable: return .secondary
        }
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "bolt.horizontal.fill" : "pause.fill")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(isActive ? .green : .orange)

            Text(isActive ? "ACTIVE MONITORING" : "PAUSED")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .kerning(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thickMaterial)
        .clipShape(Capsule())
        .frame(minWidth: 44, minHeight: 44)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let icon: String
    let title: String
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let label = actionLabel, let action = action {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(label)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Onboarding Overlay

struct OnboardingOverlay: View {
    @Binding var isPresented: Bool
    @Binding var hasCompleted: Bool
    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, detail: String)] = [
        ("camera.viewfinder", "Point Camera at Floor",
         "Hold your device so the camera sees the floor about 2 meters ahead."),
        ("figure.walk", "Step on the Green Bars",
         "Virtual guide bars appear on the ground. Walk along them at a comfortable pace."),
        ("waveform.path.ecg", "Feel the Rhythm",
         "Gentle haptic pulses guide your walking tempo. Let the rhythm lead your steps."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
                .accessibilityHidden(true)

            VStack(spacing: 32) {
                Spacer()

                let step = steps[currentStep]

                Image(systemName: step.icon)
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.green)
                    .frame(height: 80)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(step.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(step.detail)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(currentStep + 1) of 3: \(step.title). \(step.detail)")

                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Color.green : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityHidden(true)

                Spacer()

                Button {
                    if currentStep < 2 { currentStep += 1 } else { finish() }
                } label: {
                    Text(currentStep < 2 ? "Next" : "Get Started")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel(currentStep < 2 ? "Next step" : "Start using Proprio")
                .padding(.horizontal, 40)

                if currentStep == 0 {
                    Button { finish() } label: {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Skip onboarding")
                }

                Spacer().frame(height: 20)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    private func finish() {
        hasCompleted = true
        withAnimation { isPresented = false }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var haptics: HapticController
    @Binding var selectedMode: AppMode
    @Environment(\.dismiss) private var dismiss

    @AppStorage("highContrastMode") private var highContrastMode = false
    @AppStorage("hapticIntensity") private var hapticIntensity: Double = 0.7

    var body: some View {
        NavigationStack {
            List {
                // MARK: Display
                Section {
                    Toggle(isOn: $highContrastMode) {
                        Label("High Contrast", systemImage: "circle.lefthalf.filled")
                    }
                    .accessibilityLabel("High contrast mode")
                    .accessibilityValue(highContrastMode ? "On" : "Off")
                    .accessibilityHint("Switches between high contrast green on black and AR blending")
                    .frame(minHeight: 44)
                } header: {
                    Text("Display")
                } footer: {
                    Text("High contrast uses green on black for maximum visibility. AR blending overlays guides on the camera view.")
                }

                // MARK: Haptics
                Section {
                    Toggle(isOn: Binding(
                        get: { haptics.isPlayingEntrainment },
                        set: { if $0 { haptics.playGaitEntrainment() } else { haptics.stopEntrainment() } }
                    )) {
                        Label("Rhythmic Stimulation", systemImage: "metronome")
                    }
                    .accessibilityLabel("Rhythmic stimulation")
                    .accessibilityValue(haptics.isPlayingEntrainment ? "On" : "Off")
                    .accessibilityHint("Toggles rhythmic haptic pulses for gait entrainment")
                    .frame(minHeight: 44)

                    if haptics.isPlayingEntrainment {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Tempo", systemImage: "speedometer")
                                Spacer()
                                Text("\(Int(haptics.rhythmBpm)) BPM")
                                    .foregroundStyle(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                            Slider(value: $haptics.rhythmBpm, in: 40...120, step: 5)
                                .frame(minHeight: 44)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Tempo")
                        .accessibilityValue("\(Int(haptics.rhythmBpm)) beats per minute")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: haptics.rhythmBpm = min(120, haptics.rhythmBpm + 5)
                            case .decrement: haptics.rhythmBpm = max(40, haptics.rhythmBpm - 5)
                            @unknown default: break
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Haptic Intensity", systemImage: "hand.tap")
                            Spacer()
                            Text("\(Int(hapticIntensity * 100))%")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        Slider(value: $hapticIntensity, in: 0...1, step: 0.1)
                            .frame(minHeight: 44)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Haptic intensity")
                    .accessibilityValue("\(Int(hapticIntensity * 100)) percent")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: hapticIntensity = min(1.0, hapticIntensity + 0.1)
                        case .decrement: hapticIntensity = max(0.0, hapticIntensity - 0.1)
                        @unknown default: break
                        }
                    }
                } header: {
                    Text("Haptics")
                } footer: {
                    Text("Rhythmic Auditory Stimulation (RAS) delivered via wrist haptics. Adjust intensity for comfort.")
                }
                .onChange(of: hapticIntensity) { _, newValue in
                    haptics.hapticIntensity = Float(newValue)
                }

                // MARK: Mode
                Section {
                    Picker("Assistance Mode", selection: $selectedMode) {
                        ForEach(AppMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .accessibilityLabel("Assistance mode")
                    .accessibilityValue(selectedMode.rawValue)
                    .frame(minHeight: 44)
                } header: {
                    Text("Mode")
                } footer: {
                    Text(
                        selectedMode == .gait
                        ? "Gait Assistance provides walking guides and stability metrics."
                        : "Fine Motor tracks hand tremor and steadiness for precise tasks."
                    )
                }

                // MARK: Calibration
                Section {
                    Button(role: .destructive) {
                        // Placeholder
                    } label: {
                        Label("Reset Calibration", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Reset calibration")
                    .accessibilityHint("Resets motion tracking calibration data")
                    .frame(minHeight: 44)
                }

                // MARK: About
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("App version 1.0.0")
                    .frame(minHeight: 44)

                    HStack {
                        Label("Build", systemImage: "hammer")
                        Spacer()
                        Text("Swift 5.9 · iOS 17").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Built with Swift 5.9 for iOS 17")
                    .frame(minHeight: 44)
                } header: {
                    Text("About")
                } footer: {
                    Text("Proprio — Assistive technology for Parkinson's Disease, Essential Tremor, and Dyspraxia. All processing on-device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Done")
                        .accessibilityHint("Closes settings")
                }
            }
        }
    }
}
