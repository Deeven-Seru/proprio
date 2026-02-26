# Proprio: AR-Based Proprioceptive Assistant
**Swift Student Challenge 2025 Submission Candidate**

## Overview
Proprio is an iOS/iPadOS application designed to assist individuals with movement disorders (Parkinson's, Dyspraxia, Stroke recovery) by providing real-time biofeedback through AR visual cues and rhythmic haptic entrainment.

**Core Technologies:**
- **Vision Framework:** Real-time pose estimation to detect tremor amplitude and gait asymmetry.
- **ARKit/RealityKit:** Projects a visual "guide path" on the floor to overcome freezing of gait.
- **CoreHaptics:** Delivers rhythmic haptic pulses (Rhythmic Auditory Stimulation) directly to the wrist to synchronize movement.
- **CoreML:** On-device analysis of motion variance.

## Architecture
- `MotionAnalyzer`: Vision-based pose tracking and variance calculation.
- `HapticsManager`: CoreHaptics engine for rhythmic entrainment.
- `ARManager`: ARSession handling and visual overlay logic.
- `ContentView`: SwiftUI dashboard with real-time biofeedback metrics.

## Building the Project
### Prerequisites
- Xcode 15+ (iOS 17 SDK)
- GitHub Account (for CI/CD)

### Local Build
1. Clone this repository.
2. Open `Package.swift` in Xcode.
3. Select the `Proprio-iOS` scheme and a physical device (AR/Haptics require hardware).
4. Build & Run.

### GitHub Actions (CI)
This repository includes a workflow (`.github/workflows/swift.yml`) that automatically builds the project on every push to `main` using macOS runners.

## Why This Wins
This is not a game. It is a medical utility that leverages the full Apple technology stack (Vision, AR, Haptics) to solve a profound human problem. It demonstrates technical depth and empathy.

---
*Built with strategic precision.*
