import Foundation

// The Android host uses the same 12-second score. Keep both in sync with
// tests/test_mascot_motion.py, which runs the actual Swift and Java samplers.
struct MascotPose {
    var lookX = 0.0
    var lookY = 0.0
    var headX = 0.0
    var headY = 0.0
    var bob = 0.0
    var joy = 0.0
    var eyeOpen = 1.0
    var smilingEyes = false

    var eyeLineWidth: Double { 1.4 + 1.9 * eyeOpen }
    var eyeWidth: Double { 6 - 2.2 * eyeOpen }
    var eyeHeight: Double { 1.4 + 4.8 * eyeOpen }

    private static func ease(_ time: Double, _ start: Double, _ end: Double) -> Double {
        let x = max(0, min(1, (time - start) / (end - start)))
        return max(0, min(1, x * x * x * (x * (x * 6 - 15) + 10)))
    }

    private static func gaze(_ time: Double) -> (Double, Double) {
        let right = ease(time, 1.2, 1.6) - ease(time, 2.5, 3.0)
        let left = ease(time, 8.0, 8.4) - ease(time, 9.2, 9.7)
        return (0.6 * (right - left), -0.12 * left)
    }

    static func at(_ elapsed: Double) -> MascotPose {
        // Canonical microseconds keep exact blink/style boundaries stable after
        // any number of loops, despite floating-point modulo rounding.
        let time = (max(0, elapsed) * 1_000_000).rounded()
            .truncatingRemainder(dividingBy: 12_000_000) / 1_000_000
        var pose = MascotPose()
        (pose.lookX, pose.lookY) = gaze(time)
        // The eyes lead; the head follows 140 ms later, including the return.
        (pose.headX, pose.headY) = gaze(max(0, time - 0.14))
        pose.bob = sin(time / 6 * .pi * 2)
        pose.joy = 0.7 * (ease(time, 4.36, 4.9) - ease(time, 7.2, 7.75))
        for start in [4.4, 7.2, 10.3] {
            let blink = time - start
            if blink >= 0 && blink < 0.26 {
                pose.eyeOpen = blink < 0.07 ? 1 - ease(blink, 0, 0.07)
                    : ease(blink, 0.11, 0.26)
            }
        }
        // Switch eye drawings only during the fully closed part of a blink.
        pose.smilingEyes = time >= 4.49 && time < 7.29
        return pose
    }
}
