set -uo pipefail
APP="$1"
OUT="$2"
BUNDLE="space.nodeshift.music"
mkdir -p "$OUT"

stamp() {
  echo "[$(date +%H:%M:%S)] $*"
}

tmo() {
  local secs="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
}

wait_booted() {
  local udid="$1"
  tmo 300 xcrun simctl bootstatus "$udid" > /dev/null 2>&1
}

shoot_device() {
  local name="$1"
  local routes="$2"
  local udid
  udid=$(xcrun simctl list devices available -j | jq -r --arg n "$name" '.devices | to_entries[] | select(.key | test("iOS-26")) | .value[] | select(.name == $n) | .udid' | head -1)
  if [ -z "$udid" ]; then
    stamp "no simulator for $name"
    return
  fi
  local slug
  slug=$(echo "$name" | tr ' ' '-' | tr 'A-Z' 'a-z')
  stamp "boot $name $udid"
  tmo 90 xcrun simctl boot "$udid" || true
  if ! wait_booted "$udid"; then
    stamp "boot timeout for $name"
    return
  fi
  stamp "booted $name"
  tmo 30 xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  tmo 480 xcrun simctl install "$udid" "$APP" || return
  local pause=14
  for route in $routes; do
    case "$route" in
      library) args="-nsm-demo" ;;
      playing) args="-nsm-demo -nsm-playing" ;;
      lyrics) args="-nsm-demo -nsm-route lyrics -nsm-lyrics -nsm-seek 24" ;;
      *) args="-nsm-demo -nsm-route $route" ;;
    esac
    tmo 60 xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" $args > /dev/null || true
    sleep "$pause"
    pause=5
    tmo 60 xcrun simctl io "$udid" screenshot "$OUT/${slug}-${route}.png" || true
    stamp "shot $slug $route"
  done
  tmo 60 xcrun simctl shutdown "$udid" || true
}

shoot_device "iPhone 17 Pro" "library playing list playlists favorites import more storage player lyrics queue"
shoot_device "iPhone 16e" "library player lyrics"
shoot_device "iPhone 17 Pro Max" "library player lyrics"
ls -l "$OUT"
