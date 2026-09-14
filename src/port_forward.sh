#!/bin/bash

set -euo pipefail

: "${ADB_PORT:?ADB_PORT must be set}"

if ! [[ "$ADB_PORT" =~ ^[0-9]+$ ]] || (( ADB_PORT < 2 )); then
    echo "ADB_PORT must be an integer greater than 1: $ADB_PORT" >&2
    exit 1
fi

ip=$(ifconfig eth0 | awk '/inet / { print $2; exit }')
if [[ -z "$ip" ]]; then
    echo "Unable to determine the eth0 IPv4 address" >&2
    exit 1
fi

adb_port=$ADB_PORT
adb_console_port=$((ADB_PORT - 1))

socat "tcp-listen:${adb_console_port},bind=${ip},fork,reuseaddr" "tcp:127.0.0.1:${adb_console_port}" &
exec socat "tcp-listen:${adb_port},bind=${ip},fork,reuseaddr" "tcp:127.0.0.1:${adb_port}"
