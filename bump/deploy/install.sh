set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
TARGET=/opt/nsm-bump
UNIT=/etc/systemd/system/nsm-bump.service
PORT=8097

for file in nsm_bump.py presence.py requirements.txt; do
  [ -f "$SRC/$file" ] || { echo "missing $SRC/$file"; exit 1; }
done
[ -f "$HERE/nsm-bump.service" ] || { echo "missing $HERE/nsm-bump.service"; exit 1; }

python3 - "$SRC/nsm_bump.py" "$SRC/presence.py" <<'PY'
import ast
import sys

for path in sys.argv[1:]:
    ast.parse(open(path, encoding="utf-8").read(), path)
PY

install -d -m 755 "$TARGET"
if [ ! -x "$TARGET/venv/bin/python" ]; then
  python3 -m venv "$TARGET/venv"
fi
"$TARGET/venv/bin/pip" install --quiet -r "$SRC/requirements.txt"

BACKUP="$(mktemp -d)"
cp -a "$TARGET/nsm_bump.py" "$TARGET/presence.py" "$BACKUP/" 2>/dev/null || true

install -m 644 "$SRC/nsm_bump.py" "$SRC/presence.py" "$SRC/requirements.txt" "$TARGET/"
install -m 644 "$HERE/nsm-bump.service" "$UNIT"

systemctl daemon-reload
systemctl enable nsm-bump >/dev/null 2>&1
systemctl restart nsm-bump

for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$PORT/time', timeout=2)" >/dev/null 2>&1; then
    rm -rf "$BACKUP"
    echo "installed"
    exit 0
  fi
  sleep 1
done

echo "nsm-bump did not answer on port $PORT, restoring the previous files"
cp -a "$BACKUP/." "$TARGET/"
systemctl restart nsm-bump || true
journalctl -u nsm-bump -n 30 --no-pager || true
exit 1
