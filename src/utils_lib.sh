#!/bin/bash
# utils_lib.sh - Pure-logic helpers extracted from src/utils.sh.
#
# These functions contain no external-process side effects (no adb/curl/jq),
# only string/variable manipulation, so they are safe to unit-test in isolation
# with bats (see src/tests/shell/test_utils_lib.bats).
#
# src/utils.sh sources this file at startup; behaviour is unchanged. Keeping the
# testable logic here is the "split big script" step from IMPROVEMENT_ROADMAP.md
# (§5) without altering the supervisord entrypoint contract.

# Parse android version and device name.
#
# When ANDROID_VERSION carries a variant suffix (e.g. "17.0_16k"), strip the
# suffix from ANDROID_VERSION and append it to DEVICE (e.g. "pixel" ->
# "pixel-16k"). Both ANDROID_VERSION and DEVICE are mutated in place so callers
# (and the surrounding script) keep working exactly as before.
function parse_android_version_and_device() {
  # Check if ANDROID_VERSION contains a variant suffix (e.g., "17.0_16k")
  if [[ "$ANDROID_VERSION" == *"_"* ]]; then
    # Split by underscore
    IFS='_' read -r version_part suffix_part <<<"$ANDROID_VERSION"

    # Update ANDROID_VERSION to only contain the version part
    ANDROID_VERSION="$version_part"

    # Update DEVICE to include the suffix (e.g., "pixel" becomes "pixel-16k")
    DEVICE="${DEVICE}-${suffix_part}"

    echo "$(date "+%F %T") Parsed ANDROID_VERSION: $ANDROID_VERSION, DEVICE: $DEVICE"
  else
    echo "$(date "+%F %T") ANDROID_VERSION does not contain underscore, using as-is: $ANDROID_VERSION"
  fi
}

# Resolve the capability-registration alert threshold.
#
# Honours CAPABILITY_REGISTER_ALERT_THRESHOLD when it is a positive integer,
# otherwise falls back to the default of 5.
function get_capability_register_alert_threshold() {
  local threshold=${CAPABILITY_REGISTER_ALERT_THRESHOLD:-5}
  if [[ "$threshold" =~ ^[0-9]+$ ]] && [ "$threshold" -gt 0 ]; then
    echo "$threshold"
  else
    echo 5
  fi
}
