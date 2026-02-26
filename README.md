# Proprio
### Restoring Agency through Augmented Perception.

**Proprio** is a clinical-grade assistive tool designed to stabilize movement for individuals with Parkinson’s Disease, Essential Tremor, and Dyspraxia.

It bypasses damaged neural pathways by closing the loop between **visual perception** and **haptic sensation**.

---

## The Problem: Sensorimotor Disconnection
For millions, the connection between *intention* and *motion* is noisy.
- **Freezing of Gait (FoG):** The brain fails to sequence the next step.
- **Action Tremor:** Fine motor control degrades during voluntary movement.

## The Solution: Sensory Entrainment
Proprio uses the iPhone/iPad as an external cortex to provide the rhythmic cues the basal ganglia cannot.

### 1. Visual Guide Paths (ARKit)
Projects high-contrast, rhythmic visual cues onto the physical floor. This leverages **paradoxical kinesis**—allowing a patient to step *over* a virtual line when they cannot step *forward* on a blank floor.

### 2. Haptic Metronome (CoreHaptics)
Delivers precise, transient haptic pulses to the wrist (Rhythmic Auditory Stimulation methodology). This provides a temporal template for the brain to synchronize movement, reducing gait variability.

### 3. Real-Time Variance Analysis (Vision)
Tracks 19 body keypoints at 60fps using the Neural Engine. It calculates tremor amplitude and gait symmetry in real-time, adjusting feedback intensity dynamically.

---

## Technical Architecture

Built exclusively for iOS/iPadOS to leverage Apple's silicon.

| Component | Technology | Role |
|-----------|------------|------|
| **Sensation** | **CoreHaptics** | High-fidelity, transient haptic patterns for entrainment. |
| **Perception** | **ARKit + RealityKit** | World tracking, plane detection, and occlusion. |
| **Analysis** | **Vision Framework** | `VNDetectHumanBodyPoseRequest` running on Neural Engine. |
| **Interface** | **SwiftUI** | High-contrast, accessibility-first clinical HUD. |

## Privacy & Safety
- **On-Device Processing:** No video feeds leave the device. All Vision analysis happens locally.
- **Clinical Focus:** Designed for high-contrast visibility and minimal cognitive load.

## Building the Project

### Requirements
- iOS 17.0+
- iPhone with Haptic Engine (iPhone 8 or later)
- Xcode 15+

### Installation
```bash
git clone https://github.com/Deeven-Seru/haptics.git
cd haptics
open Package.swift
```
Select your physical device in Xcode (AR and Haptics do not run on Simulator) and press **Run**.

---

*Proprio is a research preview. It is not a certified medical device.*
