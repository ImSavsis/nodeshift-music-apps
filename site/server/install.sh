set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
SITE="$(cd "$SRC/../app" && pwd)"
VHOST=/etc/nginx/sites-available/music.nodeshift.space
SNIPPET=/etc/nginx/snippets/nsm-app.conf
WEB=/var/www/nsm-app

id nsmapp >/dev/null 2>&1 || useradd --system --home-dir /var/lib/nsmapp --shell /usr/sbin/nologin nsmapp

install -d -o nsmapp -g nsmapp -m 755 "$WEB" "$WEB/app" "$WEB/app/update" "$WEB/app/bin" "$WEB/app/bin/ios" "$WEB/app/bin/android" "$WEB/app/bin/win"
install -m 644 -o nsmapp -g nsmapp "$SITE/index.html" "$SITE/platform.html" "$SITE/style.css" "$SITE/app.js" "$WEB/app/"

install -d -m 755 /opt/nsm-app-sync
install -m 755 "$SRC/nsm_app_sync.py" /opt/nsm-app-sync/nsm_app_sync.py
install -m 644 "$SRC/nsm-app-sync.service" "$SRC/nsm-app-sync.timer" /etc/systemd/system/

install -d -m 755 /etc/nginx/snippets
install -m 644 "$SRC/nsm-app.conf" "$SNIPPET"

BACKUP=""
if ! grep -q "snippets/nsm-app.conf" "$VHOST"; then
  BACKUP="$VHOST.bak-nsm-$(date +%Y%m%d%H%M%S)"
  cp -a "$VHOST" "$BACKUP"
  python3 - "$VHOST" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
marker = "    location /api/music/stream/ {"
if marker not in text:
    sys.exit("marker not found in vhost")
text = text.replace(marker, "    include /etc/nginx/snippets/nsm-app.conf;\n\n" + marker, 1)
open(path, "w", encoding="utf-8").write(text)
PY
fi

if ! nginx -t; then
  if [ -n "$BACKUP" ]; then
    cp -a "$BACKUP" "$VHOST"
    echo "nginx config test failed, vhost restored from $BACKUP"
  fi
  exit 1
fi

systemctl daemon-reload
systemctl enable --now nsm-app-sync.timer
systemctl reload nginx
systemctl start nsm-app-sync.service || true
echo "installed"
