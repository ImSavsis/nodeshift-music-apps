set -u
APK="$1"
OUT="$2"
PKG="space.nodeshift.music"
CRASH=0
mkdir -p "$OUT"
adb wait-for-device
adb shell input keyevent 82 || true
adb install -r "$APK" || exit 1
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true

shoot() {
  local name="$1"
  shift
  adb shell am force-stop "$PKG"
  adb logcat -c
  adb shell am start -n "$PKG/.MainActivity" --ez nsm_demo true "$@" > /dev/null
  sleep 11
  adb exec-out screencap -p > "$OUT/$name.png"
  adb logcat -d > "$OUT/$name.log"
  if grep -q "FATAL EXCEPTION" "$OUT/$name.log"; then
    echo "crash in $name"
    CRASH=1
  fi
  echo "shot $name"
}

shoot library
shoot playing --ez nsm_playing true
shoot list --es nsm_route list
shoot playlists --es nsm_route playlists
shoot favorites --es nsm_route favorites
shoot import --es nsm_route import
shoot more --es nsm_route more
shoot storage --es nsm_route storage
shoot player --es nsm_route player --ed nsm_seek 8
shoot lyrics --es nsm_route lyrics --ez nsm_lyrics true --ed nsm_seek 24
shoot queue --es nsm_route queue
exit $CRASH
