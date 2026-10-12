set -euo pipefail
APP="$1"
OUT="$2"
BUNDLE="space.nodeshift.music"
mkdir -p "$OUT"
DEVICES=("iPhone 16e" "iPhone 17 Pro" "iPhone 17 Pro Max")
for NAME in "${DEVICES[@]}"; do
  UDID=$(xcrun simctl list devices available -j | jq -r --arg n "$NAME" '.devices | to_entries[] | select(.key | test("iOS-26")) | .value[] | select(.name == $n) | .udid' | head -1)
  if [ -z "$UDID" ]; then
    echo "no simulator for $NAME"
    continue
  fi
  SLUG=$(echo "$NAME" | tr ' ' '-' | tr 'A-Z' 'a-z')
  xcrun simctl boot "$UDID" || true
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$UDID" "$APP"
  for ROUTE in library playing list playlists favorites import more player lyrics queue; do
    xcrun simctl terminate "$UDID" "$BUNDLE" || true
    case "$ROUTE" in
      library) ARGS=(-nsm-demo) ;;
      playing) ARGS=(-nsm-demo -nsm-playing) ;;
      lyrics) ARGS=(-nsm-demo -nsm-route lyrics -nsm-lyrics -nsm-seek 24) ;;
      *) ARGS=(-nsm-demo -nsm-route "$ROUTE") ;;
    esac
    xcrun simctl launch "$UDID" "$BUNDLE" "${ARGS[@]}"
    sleep 6
    xcrun simctl io "$UDID" screenshot "$OUT/${SLUG}-${ROUTE}.png"
  done
  xcrun simctl shutdown "$UDID" || true
done
ls -l "$OUT"
