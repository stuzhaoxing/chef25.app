package com.chef25.mobile.nodespike;

// Same score as MascotMotion.swift; tested together by test_mascot_motion.py.
final class MascotMotion {
    static final class Pose {
        double lookX, lookY, headX, headY, bob, joy;
        double eyeOpen = 1;
        boolean smilingEyes;

        double eyeLineWidth() { return 1.4 + 1.9 * eyeOpen; }
        double eyeWidth() { return 6 - 2.2 * eyeOpen; }
        double eyeHeight() { return 1.4 + 4.8 * eyeOpen; }
    }

    private static double ease(double time, double start, double end) {
        double x = Math.max(0, Math.min(1, (time - start) / (end - start)));
        return Math.max(0, Math.min(1, x * x * x * (x * (x * 6 - 15) + 10)));
    }

    private static double[] gaze(double time) {
        double right = ease(time, 1.2, 1.6) - ease(time, 2.5, 3.0);
        double left = ease(time, 8.0, 8.4) - ease(time, 9.2, 9.7);
        return new double[] {0.6 * (right - left), -0.12 * left};
    }

    static Pose at(double elapsed) {
        double time = (Math.round(Math.max(0, elapsed) * 1_000_000) % 12_000_000) / 1_000_000.0;
        Pose pose = new Pose();
        double[] eyes = gaze(time);
        double[] head = gaze(Math.max(0, time - 0.14));
        pose.lookX = eyes[0];
        pose.lookY = eyes[1];
        pose.headX = head[0];
        pose.headY = head[1];
        pose.bob = Math.sin(time / 6 * Math.PI * 2);
        pose.joy = 0.7 * (ease(time, 4.36, 4.9) - ease(time, 7.2, 7.75));
        for (double start : new double[] {4.4, 7.2, 10.3}) {
            double blink = time - start;
            if (blink >= 0 && blink < 0.26) {
                pose.eyeOpen = blink < 0.07 ? 1 - ease(blink, 0, 0.07)
                    : ease(blink, 0.11, 0.26);
            }
        }
        pose.smilingEyes = time >= 4.49 && time < 7.29;
        return pose;
    }
}
