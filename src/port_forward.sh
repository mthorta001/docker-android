#!/bin/bash

#Ubuntu 16.04 -> ip=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
ip=$(ifconfig eth0 | grep 'inet' | cut -d: -f2 | awk '{ print $2}')
adb_port=$ADB_PORT
adb_console_port=$ADB_PORT-1
socat tcp-listen:$adb_console_port,bind=$ip,fork tcp:127.0.0.1:$adb_console_port &
socat tcp-listen:$adb_port,bind=$ip,fork tcp:127.0.0.1:$adb_port
