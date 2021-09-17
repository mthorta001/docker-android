#!/bin/bash

function wait_emulator_to_be_ready () {
  boot_completed=false
  while [ "$boot_completed" == false ]; do
    status=$(adb wait-for-device shell getprop sys.boot_completed | tr -d '\r')
    echo "Boot Status: $status"

    if [ "$status" == "1" ]; then
      boot_completed=true
    else
      sleep 1
    fi      
  done
}

function change_language_if_needed() {
  if [ ! -z "${LANGUAGE// }" ] && [ ! -z "${COUNTRY// }" ]; then
    wait_emulator_to_be_ready
    echo "Language will be changed to ${LANGUAGE}-${COUNTRY}"
    adb root && adb shell "setprop persist.sys.language $LANGUAGE; setprop persist.sys.country $COUNTRY; stop; start" && adb unroot
    echo "Language is changed!"
  fi
}

function install_google_play () {
  wait_emulator_to_be_ready
  echo "Google Play Service will be installed"
  adb install -r "/root/google_play_services.apk"
  echo "Google Play Store will be installed"
  adb install -r "/root/google_play_store.apk"
}

function enable_proxy_if_needed () {
  if [ "$ENABLE_PROXY_ON_EMULATOR" = true ]; then
    if [ ! -z "${HTTP_PROXY// }" ]; then
      if [[ $HTTP_PROXY == *"http"* ]]; then
        protocol="$(echo $HTTP_PROXY | grep :// | sed -e's,^\(.*://\).*,\1,g')"
        proxy="$(echo ${HTTP_PROXY/$protocol/})"
        echo "[EMULATOR] - Proxy: $proxy"

        IFS=':' read -r -a p <<< "$proxy"

        echo "[EMULATOR] - Proxy-IP: ${p[0]}"
        echo "[EMULATOR] - Proxy-Port: ${p[1]}"

        wait_emulator_to_be_ready
        echo "Enable proxy on Android emulator. Please make sure that docker-container has internet access!"
        adb root

        echo "Set up the Proxy"
        adb shell "content update --uri content://telephony/carriers --bind proxy:s:"0.0.0.0" --bind port:s:"0000" --where "mcc=310" --where "mnc=260""
        sleep 5
        adb shell "content update --uri content://telephony/carriers --bind proxy:s:"${p[0]}" --bind port:s:"${p[1]}" --where "mcc=310" --where "mnc=260""

        adb unroot

        # Mobile data need to be restarted for Android 10 or higher
        adb shell svc data disable
        adb shell svc data enable
      else
        echo "Please use http:// in the beginning!"
      fi
    else
      echo "$HTTP_PROXY is not given! Please pass it through environment variable!"
      exit 1
    fi
  fi
}


# register capability
function register_capability() {
  echo "register capability of container: emulator$APPIUM_PORT"
  curl \
  -H "accept: application/json" \
  -H "content-type: application/json" \
  -X POST "$DEVICE_SPY" \
  -d "$(cat <<EOF
  {
        "docker_container": "emulator$APPIUM_PORT",
        "hostname": "$HOST_IP",
        "devices": [
          {
            "platform": "android",
            "platform_version": "$ANDROID_VERSION",
            "device_name": "$DEVICE",
            "device_model": "$AVD_NAME",
            "udid": "$UDID",
            "adb_port": $ADB_PORT,
            "is_simulator": true,
            "labels": [
                "Emulator"
            ]
          }
        ],
        "appiums": [
          {
            "port": $APPIUM_PORT,
            "version": "$(appium --version)"
          }
        ]
  }
EOF
)"
}

# disable chrome first open welcome screen
function disable_chrome_accept_continue() {
  echo "disable chrome first open welcome screen"
  adb shell 'echo "chrome --disable-fre --no-default-browser-check --no-first-run" > /data/local/tmp/chrome-command-line' 
}

# adb enable wifi
# to resolve wifi may turn off when android 12 emulator container started
function enable_wifi() {
    echo "enable wifi"
    adb shell svc wifi enable
}

# close System UI isn't responding when start
# tap the coordinate of "Wait" button
function close_is_not_responding() {
  activity="$(adb shell dumpsys activity | grep top-activity)"
  echo "Current activity:"
  echo $activity
  echo ""
  for i in {1..180}
  do
    if [[ "$activity" == *"com.google.android.apps.nexuslauncher"* ]] || [[ "$activity" == *"com.android.settings"* ]]; then
        echo "adb tap wait button by coordinate"
        adb shell input tap 540 1059
        sleep 1
    fi
  done
}


change_language_if_needed
sleep 1
enable_proxy_if_needed
sleep 1
install_google_play
sleep 1
register_capability
sleep 1
disable_chrome_accept_continue
sleep 60
close_is_not_responding
