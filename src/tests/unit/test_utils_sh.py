"""Unit tests for src/utils.sh behavior."""
import os
import subprocess
import tempfile
from pathlib import Path
from textwrap import dedent
from unittest import TestCase


REPO_ROOT = Path(__file__).resolve().parents[3]
UTILS_SH = REPO_ROOT / "src" / "utils.sh"


class TestUtilsSh(TestCase):
    """Unit tests for Docker Android utility shell functions."""

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.calls_file = self.tmp_path / "curl_calls.log"
        self.pkill_calls_file = self.tmp_path / "pkill_calls.log"
        self.stubs_dir = self.tmp_path / "bin"
        self.stubs_dir.mkdir()
        self._write_stub_commands()

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_register_capability_treats_created_response_as_success(self):
        result = self._run_utils_function("register_capability")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Response body: {\"success\":true,\"code\":201,\"data\":{}}", result.stdout)
        self.assertIn("Capability registration successful", result.stdout)
        self.assertNotIn("Capability registration failed with status: 201", result.stdout)

    def test_ensure_capability_registered_re_registers_when_capability_is_missing(self):
        result = self._run_utils_function("ensure_capability_registered")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Capability registration missing for emulator-5856", result.stdout)
        self.assertIn("-X POST", self.calls_file.read_text())

    def test_ensure_capability_registered_alerts_after_five_registration_failures(self):
        result = self._run_utils_function(
            "for i in {1..5}; do ensure_capability_registered || true; done",
            env_overrides={"CURL_POST_STATUS": "500"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        curl_calls = self.calls_file.read_text()
        self.assertEqual(curl_calls.count("botman.int.rclabenv.com"), 1)
        self.assertIn("capability registration failed 5 times", curl_calls)

    def test_back_appium_run_and_stop_lifecycle(self):
        result = self._run_utils_function(dedent("""
            back_appium_run
            echo "PID_SET:$BACK_APPIUM_PID"
            stop_back_appium
            echo "PID_AFTER_STOP:$BACK_APPIUM_PID"
        """))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("start a new appium with command:", result.stdout)
        self.assertNotIn("--session-override", result.stdout)
        self.assertIn("Stopping auxiliary Appium server", result.stdout)
        self.assertIn("Auxiliary Appium server (PID:", result.stdout)
        self.assertIn("stopped", result.stdout)
        self.assertIn("PID_AFTER_STOP:", result.stdout)
        pkill_calls = self.pkill_calls_file.read_text() if self.pkill_calls_file.exists() else ""
        self.assertEqual(pkill_calls, "", "pkill should not be called when BACK_APPIUM_PID is tracked")

    def test_stop_back_appium_handles_already_stopped_process(self):
        result = self._run_utils_function(dedent("""
            (exit 0) &
            BACK_APPIUM_PID=$!
            export BACK_APPIUM_PID
            wait $BACK_APPIUM_PID 2>/dev/null || true
            stop_back_appium
            echo "PID_AFTER_STOP:$BACK_APPIUM_PID"
        """))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Stopping auxiliary Appium server", result.stdout)
        self.assertIn("already stopped", result.stdout)
        self.assertIn("PID_AFTER_STOP:", result.stdout)
        pkill_calls = self.pkill_calls_file.read_text() if self.pkill_calls_file.exists() else ""
        self.assertEqual(pkill_calls, "", "pkill should not be called when BACK_APPIUM_PID was tracked")

    def test_stop_back_appium_falls_back_to_pkill_when_pid_unset(self):
        result = self._run_utils_function(dedent("""
            unset BACK_APPIUM_PID
            export APPIUM_PORT2=4732
            stop_back_appium
        """))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Stopping auxiliary Appium server", result.stdout)
        self.assertIn("Auxiliary Appium server on port 4732 stopped", result.stdout)
        pkill_calls = self.pkill_calls_file.read_text() if self.pkill_calls_file.exists() else ""
        self.assertIn("-f appium -p 4732", pkill_calls)

    def _run_utils_function(self, command, env_overrides=None):
        prelude = UTILS_SH.read_text().split("\nbotman_team start emulator:", 1)[0]
        env = os.environ.copy()
        env.update({
            "ADB_PORT": "5857",
            "ANDROID_VERSION": "17.0_16k",
            "APPIUM_PORT": "4731",
            "AVD_NAME": "Pixel-4731",
            "CURL_CALLS": str(self.calls_file),
            "DEVICE": "pixel",
            "DEVICE_SPY": "https://device-spy.example/api/v1/capabilities",
            "HOST_IP": "10.32.46.151",
            "PATH": f"{self.stubs_dir}:{env['PATH']}",
            "PKILL_CALLS": str(self.pkill_calls_file),
            "TARGET_PORT": "6081",
            "UDID": "emulator-5856",
        })
        if env_overrides:
            env.update(env_overrides)
        script = dedent(f"""
            {prelude}

            {command}
        """)
        return subprocess.run(
            ["bash", "-c", script],
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def _write_stub_commands(self):
        (self.stubs_dir / "appium").write_text(dedent("""\
            #!/bin/bash
            if [[ "$*" == *"-p "* ]]; then
              trap 'exit 0' TERM INT
              while true; do sleep 0.1; done
            else
              echo "2.10.3"
            fi
        """))
        (self.stubs_dir / "pkill").write_text(dedent("""\
            #!/bin/bash
            echo "$*" >> "$PKILL_CALLS"
        """))
        (self.stubs_dir / "curl").write_text(dedent("""\
            #!/bin/bash
            echo "$*" >> "$CURL_CALLS"
            if [[ "$*" == *"botman.int.rclabenv.com"* ]]; then
              echo '{"success":true}'
            elif [[ " $* " == *" -X POST "* ]]; then
              status="${CURL_POST_STATUS:-201}"
              echo '{"success":true,"code":'"$status"',"data":{}}'
              echo "HTTP_STATUS:$status"
            else
              echo '{"success":true,"code":200,"data":[]}'
            fi
        """))
        for stub in self.stubs_dir.iterdir():
            stub.chmod(0o755)
