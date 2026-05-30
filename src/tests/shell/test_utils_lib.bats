#!/usr/bin/env bats
# Shell unit tests for the pure-logic helpers in src/utils_lib.sh.
#
# Run with: bats src/tests/shell  (or `make test-shell`).
# Install bats-core: https://github.com/bats-core/bats-core

setup() {
  # Resolve repo root from this test file location and source the library.
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  source "$REPO_ROOT/src/utils_lib.sh"
}

@test "parse_android_version_and_device strips _16k suffix into DEVICE" {
  ANDROID_VERSION="17.0_16k"
  DEVICE="pixel"
  parse_android_version_and_device
  [ "$ANDROID_VERSION" = "17.0" ]
  [ "$DEVICE" = "pixel-16k" ]
}

@test "parse_android_version_and_device leaves plain version unchanged" {
  ANDROID_VERSION="16.0"
  DEVICE="pixel"
  parse_android_version_and_device
  [ "$ANDROID_VERSION" = "16.0" ]
  [ "$DEVICE" = "pixel" ]
}

@test "get_capability_register_alert_threshold honours a valid override" {
  CAPABILITY_REGISTER_ALERT_THRESHOLD=8
  run get_capability_register_alert_threshold
  [ "$status" -eq 0 ]
  [ "$output" = "8" ]
}

@test "get_capability_register_alert_threshold falls back on non-numeric override" {
  CAPABILITY_REGISTER_ALERT_THRESHOLD="abc"
  run get_capability_register_alert_threshold
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "get_capability_register_alert_threshold falls back on zero" {
  CAPABILITY_REGISTER_ALERT_THRESHOLD=0
  run get_capability_register_alert_threshold
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "get_capability_register_alert_threshold uses default when unset" {
  unset CAPABILITY_REGISTER_ALERT_THRESHOLD
  run get_capability_register_alert_threshold
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}
