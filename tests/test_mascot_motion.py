"""Compile both production samplers and check the animation's visible contracts.

Run with python3 tests/test_mascot_motion.py (Swift compiler and JDK 17+).
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.chef25.mobile.nodespike"
FIELDS = "lookX lookY headX headY bob joy eyeOpen smilingEyes eyeLineWidth eyeWidth eyeHeight".split()


def run(command):
    return subprocess.check_output([str(x) for x in command], text=True)


class MascotMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("Swift cross-platform check requires macOS xcrun")
        cls.temp = tempfile.TemporaryDirectory(prefix="chef25-mascot-test-")
        folder = Path(cls.temp.name)
        java_home = os.environ.get("JAVA_HOME")
        java_bin = Path(java_home) / "bin" if java_home else None
        if not java_bin or not (java_bin / "javac").exists():
            # Homebrew JDKs need not be registered with macOS java_home.
            matches = sorted(Path("/opt/homebrew/opt").glob("openjdk*/libexec/openjdk.jdk/Contents/Home/bin/javac"))
            java_bin = matches[0].parent if matches else None
        javac = java_bin / "javac" if java_bin else shutil.which("javac")
        java = java_bin / "java" if java_bin else shutil.which("java")
        if not javac or not java:
            cls.temp.cleanup()
            raise unittest.SkipTest("Swift cross-platform check requires JDK 17+")
        swift_runner = folder / "Runner.swift"
        swift_values = ", ".join(f"p.{name}" for name in FIELDS if name != "smilingEyes")
        # Keep field order identical in the two compiled programs.
        swift_values = swift_values.replace("p.eyeOpen, p.eyeLineWidth", "p.eyeOpen, p.smilingEyes ? 1.0 : 0.0, p.eyeLineWidth")
        swift_runner.write_text('''import Foundation
@main struct Runner {
    static func main() {
        for index in 0...4800 {
            let p = MascotPose.at(Double(index) * 0.005)
            let values: [Double] = [VALUES]
            print(values.map { String($0) }.joined(separator: ","))
        }
    }
}
'''.replace("VALUES", swift_values))
        run(["xcrun", "swiftc", ROOT / "spike/ios-node-runtime/MascotMotion.swift", swift_runner,
             "-o", folder / "swift-runner"])
        java_runner = folder / "Runner.java"
        java_values = ", ".join("p.smilingEyes ? 1.0 : 0.0" if name == "smilingEyes" else
                                f"p.{name}()" if name.startswith("eye") and name != "eyeOpen" else
                                f"p.{name}" for name in FIELDS)
        java_runner.write_text('''package PACKAGE;
public final class Runner {
    public static void main(String[] args) {
        for (int index = 0; index <= 4800; index++) {
            MascotMotion.Pose p = MascotMotion.at(index * 0.005);
            double[] values = {VALUES};
            StringBuilder row = new StringBuilder();
            for (double value : values) { if (row.length() > 0) row.append(','); row.append(value); }
            System.out.println(row);
        }
    }
}
'''.replace("PACKAGE", PACKAGE).replace("VALUES", java_values))
        run([javac, "-d", folder, ROOT / "spike/android-node-runtime/app/src/main/java/com/chef25/mobile/nodespike/MascotMotion.java", java_runner])
        cls.swift = cls.parse(run([folder / "swift-runner"]))
        cls.android = cls.parse(run([java, "-cp", folder, PACKAGE + ".Runner"]))

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    @staticmethod
    def parse(output):
        return [dict(zip(FIELDS, map(float, line.split(',')))) for line in output.splitlines()]

    def pose(self, time):
        return self.swift[round(time / 0.005)]

    def test_platforms_match_for_two_cycles(self):
        self.assertEqual(len(self.swift), 4801)
        self.assertEqual(len(self.android), 4801)
        for left, right in zip(self.swift, self.android):
            for name in FIELDS:
                self.assertAlmostEqual(left[name], right[name], places=10, msg=name)

    def test_gaze_leads_head_without_opposing_it(self):
        for row in self.swift:
            self.assertGreaterEqual(row['lookX'] * row['headX'], -1e-10)
        self.assertGreater(self.pose(1.35)['lookX'], self.pose(1.35)['headX'])
        self.assertLess(self.pose(8.15)['lookX'], self.pose(8.15)['headX'])
        self.assertAlmostEqual(self.pose(2)['lookX'], self.pose(2)['headX'])

    def test_eye_style_changes_only_while_fully_closed(self):
        changes = []
        for index in range(1, len(self.swift)):
            if self.swift[index]['smilingEyes'] != self.swift[index - 1]['smilingEyes']:
                changes.append(index)
                self.assertEqual(self.swift[index]['eyeOpen'], 0)
                self.assertEqual(self.swift[index - 1]['eyeOpen'], 0)
        self.assertEqual(len(changes), 4)  # enter/leave smile, twice

    def test_blinks_close_hold_and_reopen_with_visible_stroke(self):
        for start in [4.4, 7.2, 10.3]:
            self.assertAlmostEqual(self.pose(start)['eyeOpen'], 1)
            self.assertAlmostEqual(self.pose(start + .09)['eyeOpen'], 0)
            self.assertAlmostEqual(self.pose(start + .26)['eyeOpen'], 1)
        for row in self.swift:
            self.assertTrue(0 <= row['eyeOpen'] <= 1)
            self.assertGreaterEqual(row['eyeLineWidth'], 1.4)

    def test_full_pose_loops_and_continuous_values_do_not_jump(self):
        for index in range(2401):
            for name in FIELDS:
                self.assertAlmostEqual(self.swift[index][name], self.swift[index + 2400][name], places=10)
        limits = dict(lookX=.02, lookY=.005, headX=.02, headY=.005, bob=.006, joy=.015, eyeOpen=.14)
        for before, after in zip(self.swift, self.swift[1:]):
            for name, limit in limits.items():
                self.assertLessEqual(abs(after[name] - before[name]), limit, name)

    def test_rest_and_smile_have_clear_holds(self):
        for time in [0, .5, 3.5, 11.5, 12]:
            row = self.pose(time)
            self.assertEqual((row['lookX'], row['headX'], row['joy'], row['eyeOpen'], row['smilingEyes']), (0, 0, 0, 1, 0))
        self.assertGreater(self.pose(5.5)['joy'], .69)
        self.assertEqual(self.pose(5.5)['smilingEyes'], 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
