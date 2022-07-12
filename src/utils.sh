#!/bin/bash

function wait_emulator_to_be_ready() {
  boot_completed=false
  while [ "$boot_completed" == false ]; do
    status=$(adb wait-for-device shell getprop sys.boot_completed | tr -d '\r')
    echo "Boot Status: $status"

    if [ "$status" == "1" ]; then
      boot_completed=true
      sleep 10
    else
      sleep 1
    fi
  done
}

function change_language_if_needed() {
  if [ ! -z "${LANGUAGE// /}" ] && [ ! -z "${COUNTRY// /}" ]; then
    wait_emulator_to_be_ready
    echo "Language will be changed to ${LANGUAGE}-${COUNTRY}"
    adb root && adb shell "setprop persist.sys.language $LANGUAGE; setprop persist.sys.country $COUNTRY; stop; start" && adb unroot
    echo "Language is changed!"
  fi
}

function install_google_play() {
  wait_emulator_to_be_ready
  echo "Google Play Service will be installed"
  adb install -r "/root/google_play_services.apk"
  echo "Google Play Store will be installed"
  adb install -r "/root/google_play_store.apk"
}

function enable_proxy_if_needed() {
  if [ "$ENABLE_PROXY_ON_EMULATOR" = true ]; then
    if [ ! -z "${HTTP_PROXY// /}" ]; then
      if [[ $HTTP_PROXY == *"http"* ]]; then
        protocol="$(echo $HTTP_PROXY | grep :// | sed -e's,^\(.*://\).*,\1,g')"
        proxy="$(echo ${HTTP_PROXY/$protocol/})"
        echo "[EMULATOR] - Proxy: $proxy"

        IFS=':' read -r -a p <<<"$proxy"

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
    -d "$(
      cat <<EOF
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
  adb shell am set-debug-app --persistent com.android.chrome
  adb shell 'echo "chrome --disable-fre --no-default-browser-check --no-first-run" > /data/local/tmp/chrome-command-line'
  adb shell am start -n com.android.chrome/com.google.android.apps.chrome.Main
  echo "$(date "+%F %T") disable chrome first open welcome screen"
}

# close System UI isn't responding when start
# tap the coordinate of "Wait" button
function handle_not_responding() {
  not_responding=$(adb shell dumpsys window windows | grep 'Not Responding')
  if [ "$not_responding" ]; then
    adb shell input tap 540 1059
    echo "$(date "+%F %T") current screen is $not_responding ,tap Wait"
    botman_team $HOST_IP:$TARGET_PORT $UDID not responding, tap Wait
  fi
}

function check_wifi() {
    WLAN=$(adb -s $UDID shell dumpsys connectivity | grep "Current state" -A 1)
    PORT=$(cut -d'-' -f2 <<<$UDID)
    ADB_DEVICE=$(adb devices)
    if [[ $ADB_DEVICE == *"$UDID"* && $ADB_DEVICE == *"device" ]]; then
      # take 1 min to wait emulator load wifi module
      RETRY=0
      while [[ $RETRY -lt 6 && $WLAN != *"WIFI"* ]]; do
          sleep 10
          # https://github.com/koalaman/shellcheck/wiki/SC2219
          (( RETRY+=1 )) || true
          echo "check wifi, wait $RETRY times..."
      done

      if [[ $WLAN != *"WIFI"* ]]; then
          echo "$ADB_DEVICE"
          echo "$WLAN"
          pkill -f "qemu-system-x86_64"
          echo "kill emulator $UDID"
          # to have enough time emulator killed
          while [[ $(adb devices) == *"$UDID"* ]]; do
              sleep 2
          done
          emulator/emulator @$AVD_NAME -port $PORT -timezone Asia/Shanghai \
              -no-boot-anim -gpu swiftshader_indirect -accel on -wipe-data -writable-system -verbose &
          echo "emulator/emulator @$AVD_NAME -port $PORT -timezone Asia/Shanghai -no-boot-anim -gpu swiftshader_indirect -accel on -wipe-data -writable-system -verbose &"
          botman_team $HOST_IP:$TARGET_PORT $UDID no wifi, recreate emulator
          wait_emulator_to_be_ready
      fi
    fi
}

# install appium settings app
# refer to:
# https://www.headspin.io/blog/special-capabilities-for-speeding-up-android-test-initialization?utm_source=gold_browser_extension
# https://discuss.appium.io/t/appium-settings-app-is-not-running-after-5000ms/36218/6
APPIUM_SETTINGS_PATH=/usr/lib/node_modules/appium/node_modules/io.appium.settings/apks/settings_apk-debug.apk
UIAUTOMATOR2_PATH=$(ls /usr/lib/node_modules/appium/node_modules/appium-uiautomator2-server/apks/appium-uiautomator2-server-v*.apk)
function adb_install() {
  if [[ -z $(adb shell pm list packages io.appium.settings) ]]; then
    adb install $APPIUM_SETTINGS_PATH
    echo "$(date "+%F %T") adb install appium settings app $APPIUM_SETTINGS_PATH"
  fi
#  if [[ -z $(adb shell pm list packages io.appium.uiautomator2.server) ]]; then
#    adb install $UIAUTOMATOR2_PATH
#    echo "$(date "+%F %T") adb install uiautomator2 app $UIAUTOMATOR2_PATH"
#  fi
}

TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InN3YWluLnpoZW5nQHJpbmdjZW50cmFsLmNvbSIsInNlcnZpY2UiOiJzd2Fpbi56aGVuZyIsInJvbGUiOiJST0xFX1VTRVIiLCJpYXQiOjE2NTA4Njg5MTcsImV4cCI6MTk2NjIyODkxN30.ZGy1aqx6e8yGMMqmiOkRuB1Rf44Y5vkLkVIURMmSRXA
function botman_user() {
  curl -X POST "https://botman.lab.nordigy.ru/v2/user/message" \
    -H "Authorization: Bearer $TOKEN" \
    -H "content-type: application/json" \
    -d "{ \"email\": \"swain.zheng@ringcentral.com\", \"message\": \"$TIME  $*\" }"
}

function botman_team() {
    curl -X POST "https://botman.lab.nordigy.ru/v2/team/message" \
    -H "Authorization: Bearer $TOKEN" \
    -H "content-type: application/json" \
    -d "{ \"mentionList\": [\"swain.zheng@ringcentral.com\"], \"teamName\": \"Emulator$(cut -d'.' -f4 <<<$HOST_IP)\", \"message\": \"$TIME  $*\" }"
}

botman_team start emulator: $HOST_IP:$TARGET_PORT $UDID
wait_emulator_to_be_ready
#change_language_if_needed
#sleep 1
#enable_proxy_if_needed
#sleep 1
register_capability
sleep 1
disable_chrome_accept_continue
sleep 1
adb_install
sleep 1
echo "$(date "+%F %T") start checking..."
while true; do
  handle_not_responding
  check_wifi
  adb_install
  sleep 10
done
