#!/bin/bash

DATETIME=$(date "+%F %T")

function wait_emulator_to_be_ready() {
  boot_completed=false
  while [ "$boot_completed" == false ]; do
    status=$(adb wait-for-device shell getprop sys.boot_completed | tr -d '\r')
    echo "$(date "+%F %T") Boot Status: $status"

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

MTHOR_HOST=http://aqa01-i01-xta02.lab.nordigy.ru:10000
MTHOR_LOCK_DEVICE=$MTHOR_HOST/api/v1/device-locks
MTHOR_UNLOCK_DEVICE=$MTHOR_HOST/api/v1/device-locks/$UDID
function lock_device() {
    echo "lock device: $UDID 2 minutes"
    curl \
      -H "accept: application/json" \
      -H "content-type: application/json" \
      -X POST "$MTHOR_LOCK_DEVICE" \
      -d "
    {
        \"udid\": \"$UDID\",
        \"timeout\": 10
    }"
}

function unlock_device() {
    echo "unlock device: $UDID"
    curl \
      -H "accept: application/json" \
      -H "content-type: application/json" \
      -X DELETE "$MTHOR_UNLOCK_DEVICE"
}

# register capability
function register_capability() {
  echo "$(date "+%F %T") register capability of container: emulator$APPIUM_PORT"
  response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
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
    )")
  http_body=$(echo "$response" | sed -e 's/HTTP_STATUS\:.*//g')
  http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
  echo "$(date "+%F %T") Response body: $http_body"
  if [ "$http_status" -eq 200 ]; then
    echo "$(date "+%F %T") Capability registration successful"
  else
    echo "$(date "+%F %T") Capability registration failed with status: $http_status"
  fi
}

# https://stackoverflow.com/questions/60444428/android-skip-chrome-welcome-screen-using-adb
# disable chrome first open welcome screen
function disable_chrome_accept_continue() {
  adb shell am set-debug-app --persistent com.android.chrome
  adb shell 'echo "chrome --disable-fre --no-default-browser-check --no-first-run" > /data/local/tmp/chrome-command-line'
  adb shell am start -n com.android.chrome/com.google.android.apps.chrome.Main
  echo "$(date "+%F %T") disable chrome first open welcome screen"
}

function back_appium_run() {
  ((APPIUM_PORT2 = $APPIUM_PORT + 1))
  export APPIUM_PORT2=$APPIUM_PORT2
  echo "$(date "+%F %T") APPIUM_PORT2 set to: $APPIUM_PORT2"
  cmd="appium -p $APPIUM_PORT2 --relaxed-security --log-timestamp --local-timezone --session-override \
        --base-path /wd/hub --use-plugins=relaxed-caps,images"
  echo "$(date "+%F %T") start a new appium with command:\n $cmd"
  nohup $cmd > /dev/null 2>&1 &
}


function check_appium_server_repeatedly() {
  local retries=5
  local interval=2
  local attempts=0
  local appium_port=$APPIUM_PORT2

  while [ $attempts -lt $retries ]; do
    local status=$(curl -s http://127.0.0.1:$appium_port/wd/hub/status)
    echo "$(date "+%F %T") appium status: $status"
    local response=$(echo $status | jq -r '.value.ready')

    if [ "$response" = "true" ]; then
      echo "$(date "+%F %T") Appium server is running on port $appium_port"
      return 0
    else
      ((attempts++))
      echo "$(date "+%F %T") Attempt $attempts: Appium server not running on port $appium_port, waiting $interval second..."
      sleep $interval
    fi
  done

  echo "$(date "+%F %T") Exceeded maximum retries. Appium server is not running on port $appium_port"
  return 1
}

# Deprecated
function check_appium_server() {
  local status=$(curl -s http://127.0.0.1:$APPIUM_PORT2/wd/hub/status)
  echo "$(date "+%F %T") appium status: $status"
  local response=$(echo $status | jq -r '.value.ready')
  if [ "$response" = "true" ]; then
    echo "$(date "+%F %T") Appium server is running on port $APPIUM_PORT2"
    return 0
  else
    echo "$(date "+%F %T") Appium server is not running on port $APPIUM_PORT2"
    return 1
  fi
}

CHROME_NO_THANKS_BTN_ID="com.android.chrome:id/negative_button"
function handle_chrome_alert() {
  if ! check_appium_server_repeatedly; then
    echo "$(date "+%F %T") Appium server is not running. Exiting."
    return 1
  fi

  SESSION_ID=$(curl -s -X POST http://127.0.0.1:${APPIUM_PORT2}/wd/hub/session -H "Content-Type: application/json" -d '{
      "capabilities": {
        "alwaysMatch": {
          "platformName": "android",
          "udid": "'"${UDID}"'",
          "appPackage": "com.android.chrome",
          "appActivity": "com.google.android.apps.chrome.Main",
          "automationName": "UiAutomator2",
          "newCommandTimeout": "180"
        },
        "firstMatch": [{}]
      }
    }' | jq -r '.value.sessionId')
    echo "$(date "+%F %T") Session ID: $SESSION_ID"
  
  ELEMENT_ID="null"
  for i in {1..10}; do
    ELEMENT_ID=$(curl -s -X POST http://127.0.0.1:${APPIUM_PORT2}/wd/hub/session/$SESSION_ID/element -H "Content-Type: application/json" -d '{
      "using": "id",
      "value": "'"$CHROME_NO_THANKS_BTN_ID"'"
      }' | jq -r '.value.ELEMENT')
    if [ "$ELEMENT_ID" != "null" ]; then
      echo "$(date "+%F %T") Element ID: $ELEMENT_ID"
      curl -X POST http://127.0.0.1:$APPIUM_PORT2/wd/hub/session/$SESSION_ID/element/$ELEMENT_ID/click -H "Content-Type: application/json"
      echo "$(date "+%F %T") Button clicked"
      break
    else
      echo "Element not found, retrying... ($i)"
      sleep 2
    fi
  done
  curl -s -X DELETE http://127.0.0.1:$APPIUM_PORT2/wd/hub/session/$SESSION_ID
  echo "$(date "+%F %T") Session closed"
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
      # take 2 min to wait emulator load wifi module
      RETRY=0
      while [[ $RETRY -lt 12 && $WLAN != *"WIFI"* ]]; do
          sleep 10
          # https://github.com/koalaman/shellcheck/wiki/SC2219
          (( RETRY+=1 )) || true
          echo "check wifi, wait $RETRY times..."
      done

      if [[ $WLAN != *"WIFI"* ]]; then
          echo "$ADB_DEVICE"
          echo "$WLAN"
          while [ $(curl --request GET -sL \
           --url "http://$HOST_IP:$APPIUM_PORT/wd/hub/sessions" | jq -c '.value[0].id') != 'null' ]; do
             echo "session id: $(curl --request GET -sL \
                --url "http://$HOST_IP:$APPIUM_PORT/wd/hub/sessions" | jq -c '.value[0].id'), sleep 2s..."
              sleep 2
          done
          pkill -f "qemu-system-x86_64"
          echo "kill emulator $UDID"
          lock_device
          # to have enough time emulator killed
          while [[ $(adb devices) == *"$UDID"* ]]; do
              sleep 2
          done
          emulator/emulator @$AVD_NAME -port $PORT -timezone Asia/Shanghai \
              -no-boot-anim -gpu swiftshader_indirect -accel on -wipe-data -writable-system -verbose -dns-server 10.32.51.10,10.32.51.55 &
          echo "emulator/emulator @$AVD_NAME -port $PORT -timezone Asia/Shanghai -no-boot-anim -gpu swiftshader_indirect -accel on -wipe-data -writable-system -verbose &"
          botman_team $HOST_IP:$TARGET_PORT $UDID no wifi, recreate emulator
          wait_emulator_to_be_ready
          unlock_device
          disable_chrome_accept_continue
      fi
    fi
}

# install appium settings app
# refer to:
# https://www.headspin.io/blog/special-capabilities-for-speeding-up-android-test-initialization?utm_source=gold_browser_extension
# https://discuss.appium.io/t/appium-settings-app-is-not-running-after-5000ms/36218/6
APPIUM_SETTINGS_PATH=/root/.appium/node_modules/appium-uiautomator2-driver/node_modules/io.appium.settings/apks/settings_apk-debug.apk
UIAUTOMATOR2_PATH=$(ls /root/.appium/node_modules/appium-uiautomator2-driver/node_modules/appium-uiautomator2-server/apks/appium-uiautomator2-server-v*.apk)
function adb_install_appium_settings() {
  if [[ -z $(adb shell pm list packages io.appium.settings) ]]; then
    adb install $APPIUM_SETTINGS_PATH
    echo "$(date "+%F %T") adb install appium settings app $APPIUM_SETTINGS_PATH"
  fi
#  if [[ -z $(adb shell pm list packages io.appium.uiautomator2.server) ]]; then
#    adb install $UIAUTOMATOR2_PATH
#    echo "$(date "+%F %T") adb install uiautomator2 app $UIAUTOMATOR2_PATH"
#  fi
}

function health_check_adb_devices() {
  adb_devices=$(adb devices)
  devices=$(adb devices | grep -w "device" | grep -v "List")
  if [ -z "$devices" ]; then
    echo "$(date "+%F %T") no devices connected ==> $adb_devices"
    return 1
  else 
    return 0
  fi
}

DEVICE_SPY_EXEC_CMD=http://aqa01-i01-xta02.lab.nordigy.ru:10000/api/v1/hosts/exec_cmd
function exec_remote_cmd() {
  local hostname=$1
  local command=$2
  local timeout=${3:-60}
  curl -X POST "$DEVICE_SPY_EXEC_CMD" \
    -H "accept: application/json" \
    -H "content-type: application/json" \
    -d "{\"hostname\": \"$hostname\", \"cmd\": \"$command\", \"timeout\": $timeout}"
}

TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InN3YWluLnpoZW5nQHJpbmdjZW50cmFsLmNvbSIsInNlcnZpY2UiOiJzd2Fpbi56aGVuZyIsInJvbGUiOiJST0xFX1VTRVIiLCJpYXQiOjE2NTA4Njg5MTcsImV4cCI6MTk2NjIyODkxN30.ZGy1aqx6e8yGMMqmiOkRuB1Rf44Y5vkLkVIURMmSRXA
function botman_user() {
  curl -X POST "https://botman.int.rclabenv.com/v2/user/message" \
    -H "Authorization: Bearer $TOKEN" \
    -H "content-type: application/json" \
    -d "{ \"email\": \"swain.zheng@ringcentral.com\", \"message\": \"$DATETIME  $*\" }"
}

function botman_team() {
    curl -X POST "https://botman.int.rclabenv.com/v2/team/message" \
    -H "Authorization: Bearer $TOKEN" \
    -H "content-type: application/json" \
    -d "{ \"mentionList\": [\"swain.zheng@ringcentral.com\"], \"teamName\": \"Emulator$(cut -d'.' -f4 <<<$HOST_IP)\", \"message\": \"$DATETIME  $*\" }"
}

function replaceNoVncPython() {
    sed -i 's/python/python3/g' /root/noVNC/utils/websockify/run
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
adb_install_appium_settings
sleep 1
replaceNoVncPython
sleep 1
back_appium_run
sleep 1
handle_chrome_alert

echo "$(date "+%F %T") start while checking..."
no_device_count=0
max_no_device_count=5
while true; do
  if health_check_adb_devices; then
    handle_not_responding

  # wifi monitor has implement on mthor code
  # after case failed
  # check_wifi
    adb_install_appium_settings
  else
    no_device_count=$((no_device_count + 1))
    if [ "$no_device_count" -ge "$max_no_device_count" ]; then
      echo "$(date "+%F %T") No devices connected for $max_no_device_count cycles. Exiting."
      local command="docker-compose up -d --force-recreate emulator$APPIUM_PORT"
      echo "$DATETIME execute command ==> $command"
      botman_team no device found and start emulator: $HOST_IP:$TARGET_PORT $UDID
      exec_remote_cmd $HOST_IP $command
      break
    fi
  fi
  sleep 10
done
