import asyncio
import functools
import hashlib
import json
import logging
import math
import os
import re
import secrets
import time
from collections import deque
from pathlib import Path
from urllib.parse import urlsplit

import aiohttp
from aiohttp import WSMsgType, web

log = logging.getLogger("nsm.presence")


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


SITE_ME_URL = os.environ.get("NSM_SITE_ME_URL", "https://music.nodeshift.space/api/auth/me")
PUBLIC_BASE = os.environ.get("NSM_PUBLIC_BASE", "https://music.nodeshift.space/app/bump")
ART_DIR = Path(os.environ.get("NSM_ART_DIR", "/var/lib/nsm-bump/art"))
COVER_HOSTS = os.environ.get("NSM_COVER_HOSTS", "burmalda.savsis.xyz,music.nodeshift.space")
COVER_LIMIT = 256

ART_PATH = "/presence/art"
JSON_LIMIT = 4096
MAX_ART_BYTES = 700_000
ART_REQUEST_LIMIT = MAX_ART_BYTES
ART_USER_MAX_FILES = 200
ART_USER_MAX_BYTES = 50_000_000
ART_RATE_LIMIT = 10
ART_RATE_WINDOW_SECONDS = 60
ART_TOTAL_MAX_BYTES = env_int("NSM_ART_MAX_TOTAL_BYTES", 4_000_000_000)
ART_MAX_IDLE_SECONDS = env_int("NSM_ART_MAX_IDLE_DAYS", 90) * 86400
ART_TOUCH_AFTER_SECONDS = 86400
ART_PRUNE_INTERVAL_SECONDS = 3600
ART_INDEX_NAME = "owners.json"
ART_NAME = re.compile(r"^[a-f0-9]{40}\.(jpg|png)$")
ART_TYPES = {
    "image/jpeg": ("jpg", b"\xff\xd8\xff"),
    "image/png": ("png", b"\x89PNG\r\n\x1a\n"),
}

TOKEN_TTL_SECONDS = 300
DENIED_TTL_SECONDS = 30
TOKEN_CACHE_LIMIT = 5000
VERIFY_RATE_LIMIT = 30
VERIFY_RATE_WINDOW_SECONDS = 60
UPSTREAM_TIMEOUT_SECONDS = 8
DEFAULT_RETRY_AFTER = 5

PLAYING_TTL_SECONDS = 70
PAUSED_TTL_SECONDS = env_int("NSM_PAUSED_TTL_SECONDS", 1200)
SWEEP_INTERVAL_SECONDS = 20
POSITION_JUMP_MS = 2500
MAX_TIME_MS = 86_400_000
MAX_DEVICES_PER_USER = 8
MAX_SINKS_PER_USER = 6
SINK_SEND_TIMEOUT_SECONDS = 5
PRIVATE_FIELDS = ("seen", "since")
CONTENT_FIELDS = ("device", "platform", "playing", "title", "artist", "album", "duration_ms", "cover", "site_id")
SITE_ID = re.compile(r"^[0-9]{1,12}$")


def now_ms() -> int:
    return int(time.time() * 1000)


def clip(value, limit: int) -> str:
    return str(value or "").strip()[:limit]


def number(value) -> int:
    try:
        parsed = int(float(value))
    except (TypeError, ValueError, OverflowError):
        return 0
    return min(MAX_TIME_MS, max(0, parsed))


def cover_hosts() -> set[str]:
    hosts = {host.strip().lower() for host in COVER_HOSTS.split(",") if host.strip()}
    base = urlsplit(PUBLIC_BASE).hostname
    if base:
        hosts.add(base)
    return hosts


def cover_url(value) -> str:
    url = str(value or "").strip()
    if not url or len(url) > COVER_LIMIT or re.search(r"\s", url):
        return ""
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError:
        return ""
    if parts.scheme != "https" or port not in (None, 443) or parts.username or parts.password:
        return ""
    return url if (parts.hostname or "") in cover_hosts() else ""


def token_key(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def client_ip(request: web.Request) -> str:
    if request.remote in ("127.0.0.1", "::1"):
        forwarded = request.headers.get("X-Forwarded-For", "")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.remote or "unknown"


def throttle(windows: dict[str, deque], key: str, now: int, limit: int, window_seconds: int) -> int:
    span = window_seconds * 1000
    window = windows.setdefault(key, deque())
    while window and now - window[0] >= span:
        window.popleft()
    if len(window) >= limit:
        return max(1, math.ceil((window[0] + span - now) / 1000))
    window.append(now)
    return 0


def forget_idle(windows: dict[str, deque], now: int, window_seconds: int) -> None:
    span = window_seconds * 1000
    for key in [name for name, window in windows.items() if not window or now - window[-1] >= span]:
        del windows[key]


def same_track(first: dict, second: dict) -> bool:
    return (first["title"], first["artist"], first["playing"]) == (second["title"], second["artist"], second["playing"])


def meaningful_change(previous: dict | None, current: dict | None) -> bool:
    if previous is None or current is None:
        return previous is not current
    if any(previous[field] != current[field] for field in CONTENT_FIELDS):
        return True
    expected = previous["position_ms"] + (current["ts"] - previous["ts"] if previous["playing"] else 0)
    return abs(current["position_ms"] - expected) > POSITION_JUMP_MS


def sink_message(state: dict | None) -> dict:
    return {"type": "presence", **state} if state else {"type": "clear"}


class Unavailable(Exception):
    status = 503
    reason = "unavailable"

    def __init__(self, retry_after: int = DEFAULT_RETRY_AFTER) -> None:
        super().__init__(f"{self.reason}, retry after {retry_after}s")
        self.retry_after = retry_after


class Throttled(Unavailable):
    status = 429
    reason = "slow down"


class PresenceHub:
    def __init__(self, epoch: int | None = None) -> None:
        self.epoch = int(time.time()) if epoch is None else epoch
        self.sinks: dict[str, set[web.WebSocketResponse]] = {}
        self.states: dict[str, dict[str, dict]] = {}
        self.published: dict[str, dict | None] = {}
        self.tokens: dict[str, tuple[str, int]] = {}
        self.denied: dict[str, int] = {}
        self.verifications: dict[str, deque] = {}
        self.versions: dict[str, int] = {}
        self.waiters: dict[str, asyncio.Condition] = {}

    def condition(self, user: str) -> asyncio.Condition:
        return self.waiters.setdefault(user, asyncio.Condition())

    def version(self, user: str) -> int:
        return self.versions.get(user, self.epoch)

    def clean(self, body: dict, now: int | None = None) -> dict | None:
        title = clip(body.get("title"), 128)
        if not title:
            return None
        site_id = clip(body.get("site_id"), 12)
        duration = number(body.get("duration_ms"))
        position = number(body.get("position_ms"))
        if duration > 0:
            position = min(position, duration)
        return {
            "device": clip(body.get("device"), 64),
            "platform": clip(body.get("platform"), 16),
            "playing": body.get("playing") is True,
            "title": title,
            "artist": clip(body.get("artist"), 128),
            "album": clip(body.get("album"), 128),
            "position_ms": position,
            "duration_ms": duration,
            "cover": cover_url(body.get("cover")),
            "site_id": site_id if SITE_ID.match(site_id) else "",
            "ts": now_ms() if now is None else now,
        }

    def store(self, user: str, slot: dict, now: int | None = None) -> None:
        now = now_ms() if now is None else now
        slots = self.states.setdefault(user, {})
        previous = slots.get(slot["device"])
        slot["seen"] = now
        slot["since"] = now
        if previous is not None and same_track(previous, slot):
            slot["since"] = previous["since"]
            expected = previous["position_ms"] + (now - previous["ts"] if previous["playing"] else 0)
            if abs(slot["position_ms"] - expected) <= POSITION_JUMP_MS:
                slot["position_ms"] = previous["position_ms"]
                slot["ts"] = previous["ts"]
        if previous is None and len(slots) >= MAX_DEVICES_PER_USER:
            del slots[min(slots, key=lambda key: slots[key]["seen"])]
        slots[slot["device"]] = slot

    def remove(self, user: str, device: str) -> None:
        slots = self.states.get(user)
        if not slots:
            return
        if device:
            slots.pop(device, None)
        else:
            slots.clear()
        if not slots:
            del self.states[user]

    def expire(self, now: int | None = None) -> list[str]:
        now = now_ms() if now is None else now
        touched = []
        for user, slots in list(self.states.items()):
            for key, slot in list(slots.items()):
                ttl = PLAYING_TTL_SECONDS if slot["playing"] else PAUSED_TTL_SECONDS
                if now - slot["seen"] > ttl * 1000:
                    del slots[key]
                    if user not in touched:
                        touched.append(user)
            if not slots:
                del self.states[user]
        return touched

    def effective(self, user: str) -> dict | None:
        slots = self.states.get(user)
        if not slots:
            return None
        playing = [slot for slot in slots.values() if slot["playing"]]
        pool = playing or list(slots.values())
        return max(pool, key=lambda slot: (slot["since"], slot["seen"], slot["device"]))

    def payload(self, user: str, now: int | None = None) -> dict | None:
        slot = self.published.get(user)
        if slot is None:
            return None
        now = now_ms() if now is None else now
        state = {key: value for key, value in slot.items() if key not in PRIVATE_FIELDS}
        state["age_ms"] = max(0, now - slot["ts"])
        return state

    async def publish(self, user: str) -> bool:
        current = self.effective(user)
        if not meaningful_change(self.published.get(user), current):
            return False
        self.published[user] = dict(current) if current else None
        self.versions[user] = self.version(user) + 1
        condition = self.condition(user)
        async with condition:
            condition.notify_all()
        await self.notify(user)
        return True

    async def sweep(self) -> None:
        forget_idle(self.verifications, now_ms(), VERIFY_RATE_WINDOW_SECONDS)
        for user in self.expire():
            await self.publish(user)

    async def notify(self, user: str) -> None:
        sinks = list(self.sinks.get(user, ()))
        if not sinks:
            return
        message = sink_message(self.payload(user))
        results = await asyncio.gather(*(self.send(sink, message) for sink in sinks))
        for sink, delivered in zip(sinks, results):
            if not delivered:
                self.sinks.get(user, set()).discard(sink)

    async def send(self, sink: web.WebSocketResponse, message: dict) -> bool:
        if sink.closed:
            return False
        try:
            await asyncio.wait_for(sink.send_json(message), timeout=SINK_SEND_TIMEOUT_SECONDS)
        except Exception as error:
            log.warning("dropping presence sink: %r", error)
            return False
        return True

    def remember(self, key: str, user: str | None, now: int) -> None:
        if user is None:
            self.denied[key] = now + DENIED_TTL_SECONDS * 1000
        else:
            self.tokens[key] = (user, now + TOKEN_TTL_SECONDS * 1000)
        if len(self.tokens) > TOKEN_CACHE_LIMIT:
            self.tokens = {name: entry for name, entry in self.tokens.items() if entry[1] > now}
            if len(self.tokens) > TOKEN_CACHE_LIMIT:
                self.tokens.clear()
        if len(self.denied) > TOKEN_CACHE_LIMIT:
            self.denied = {name: until for name, until in self.denied.items() if until > now}
            if len(self.denied) > TOKEN_CACHE_LIMIT:
                self.denied.clear()


def write_atomic(target: Path, data: bytes) -> None:
    temp = target.with_name(f".{target.name}.{secrets.token_hex(6)}.tmp")
    try:
        with open(temp, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, target)
    except BaseException:
        temp.unlink(missing_ok=True)
        raise


class ArtStore:
    def __init__(self) -> None:
        self.root: Path | None = None
        self.sizes: dict[str, int] = {}
        self.owners: dict[str, set[str]] = {}
        self.uploads: dict[str, deque] = {}
        self.pruned_at = 0.0

    def attach(self) -> Path:
        if self.root != ART_DIR:
            self.root = ART_DIR
            self.load()
        return self.root

    def load(self) -> None:
        self.sizes = {}
        self.owners = {}
        if not self.root.is_dir():
            return
        for entry in self.root.iterdir():
            if ART_NAME.match(entry.name) and entry.is_file():
                self.sizes[entry.name] = entry.stat().st_size
            elif entry.name.startswith(".") and entry.name.endswith(".tmp"):
                entry.unlink(missing_ok=True)
        try:
            raw = json.loads((self.root / ART_INDEX_NAME).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            raw = {}
        if not isinstance(raw, dict):
            return
        for user, names in raw.items():
            kept = {name for name in names if isinstance(name, str) and name in self.sizes} if isinstance(names, list) else set()
            if kept:
                self.owners[str(user)] = kept

    def save(self) -> None:
        index = {user: sorted(names) for user, names in self.owners.items() if names}
        write_atomic(self.root / ART_INDEX_NAME, json.dumps(index).encode("utf-8"))

    def throttle(self, user: str, now: int) -> int:
        return throttle(self.uploads, user, now, ART_RATE_LIMIT, ART_RATE_WINDOW_SECONDS)

    def put(self, user: str, name: str, data: bytes) -> str:
        root = self.attach()
        path = root / name
        if not self.fits(self.owners.get(user, set()) - {name}, len(data)) and not self.evict_for(user, name, len(data)):
            return "quota"
        if name in self.sizes and path.is_file():
            os.utime(path)
        else:
            if sum(self.sizes.values()) + len(data) > ART_TOTAL_MAX_BYTES:
                return "full"
            root.mkdir(parents=True, exist_ok=True)
            write_atomic(path, data)
            self.sizes[name] = len(data)
        owned = self.owners.setdefault(user, set())
        if name not in owned:
            owned.add(name)
            self.save()
        return "ok"

    def fits(self, owned: set[str], size: int) -> bool:
        used = sum(self.sizes.get(name, 0) for name in owned)
        return len(owned) < ART_USER_MAX_FILES and used + size <= ART_USER_MAX_BYTES

    def evict_for(self, user: str, name: str, size: int) -> bool:
        if size > ART_USER_MAX_BYTES:
            return False
        owned = self.owners.get(user, set())

        def idle_since(candidate: str) -> tuple[float, str]:
            try:
                return ((self.root / candidate).stat().st_mtime, candidate)
            except OSError:
                return (0.0, candidate)

        for victim in sorted(owned - {name}, key=idle_since):
            if self.fits(owned - {name}, size):
                break
            owned.discard(victim)
            if not any(victim in names for names in self.owners.values()):
                (self.root / victim).unlink(missing_ok=True)
                self.sizes.pop(victim, None)
        self.owners = {holder: names for holder, names in self.owners.items() if names}
        self.save()
        return self.fits(owned - {name}, size)

    def touch(self, path: Path, now: float) -> None:
        try:
            if now - path.stat().st_mtime > ART_TOUCH_AFTER_SECONDS:
                os.utime(path)
        except OSError:
            pass

    def prune(self, now: float | None = None) -> int:
        self.attach()
        cutoff = (time.time() if now is None else now) - ART_MAX_IDLE_SECONDS
        gone = []
        for name in list(self.sizes):
            path = self.root / name
            try:
                idle = path.stat().st_mtime < cutoff
            except OSError:
                gone.append(name)
                continue
            if idle:
                path.unlink(missing_ok=True)
                gone.append(name)
        for name in gone:
            self.sizes.pop(name, None)
            for names in self.owners.values():
                names.discard(name)
        self.owners = {user: names for user, names in self.owners.items() if names}
        if gone:
            self.save()
        return len(gone)


def json_response(payload: dict, status: int = 200, headers: dict | None = None) -> web.Response:
    return web.json_response(payload, status=status, headers={"Cache-Control": "no-store", **(headers or {})})


def retry_after_of(response: aiohttp.ClientResponse) -> int:
    raw = response.headers.get("Retry-After", "")
    return min(60, max(1, int(raw))) if raw.isdigit() else DEFAULT_RETRY_AFTER


async def verify_site_token(session: aiohttp.ClientSession, token: str) -> str | None:
    try:
        async with session.get(SITE_ME_URL, headers={"Authorization": f"Bearer {token}"}) as response:
            if response.status in (401, 403):
                return None
            if response.status != 200:
                log.warning("site auth answered %s", response.status)
                raise Unavailable(retry_after_of(response))
            data = await response.json()
    except Unavailable:
        raise
    except (aiohttp.ClientError, asyncio.TimeoutError, ValueError) as error:
        log.warning("site auth unreachable: %r", error)
        raise Unavailable() from error
    if not isinstance(data, dict):
        log.warning("site auth returned %s instead of an object", type(data).__name__)
        raise Unavailable()
    value = data.get("id")
    return str(value) if value is not None else None


def upstream_verifier(app: web.Application):
    async def verify(token: str) -> str | None:
        return await verify_site_token(app["presence_http"], token)

    return verify


async def identify(request: web.Request) -> str | None:
    hub: PresenceHub = request.app["presence"]
    header = request.headers.get("Authorization", "")
    token = header[7:].strip() if header[:7].lower() == "bearer " else ""
    if not token or len(token) > 4096:
        return None
    key = token_key(token)
    now = now_ms()
    cached = hub.tokens.get(key)
    if cached and cached[1] > now:
        return cached[0]
    if hub.denied.get(key, 0) > now:
        return None
    wait = throttle(hub.verifications, client_ip(request), now, VERIFY_RATE_LIMIT, VERIFY_RATE_WINDOW_SECONDS)
    if wait:
        raise Throttled(wait)
    try:
        user = await request.app["verify"](token)
    except Unavailable:
        raise
    except Exception as error:
        log.exception("token verification crashed")
        raise Unavailable() from error
    hub.remember(key, user, now)
    return user


def authed(handler):
    @functools.wraps(handler)
    async def wrapper(request: web.Request) -> web.StreamResponse:
        try:
            user = await identify(request)
        except Unavailable as error:
            return json_response({"error": error.reason}, error.status, {"Retry-After": str(error.retry_after)})
        if user is None:
            return json_response({"error": "unauthorized"}, 401)
        return await handler(request, user)

    return wrapper


@web.middleware
async def limit_body(request: web.Request, handler):
    limit = ART_REQUEST_LIMIT if request.path == ART_PATH else JSON_LIMIT
    if request.content_length is not None and request.content_length > limit:
        return json_response({"error": "too large"}, 413)
    return await handler(request)


async def read_body(request: web.Request) -> dict | None:
    try:
        body = await request.json()
    except web.HTTPException:
        raise
    except Exception:
        return None
    return body if isinstance(body, dict) else None


@authed
async def handle_update(request: web.Request, user: str) -> web.Response:
    hub: PresenceHub = request.app["presence"]
    body = await read_body(request)
    if body is None:
        return json_response({"error": "bad json"}, 400)
    if body.get("stop") is True:
        hub.remove(user, clip(body.get("device"), 64))
        await hub.publish(user)
        return json_response({"ok": True})
    slot = hub.clean(body)
    if slot is None:
        return json_response({"error": "title required"}, 400)
    hub.store(user, slot)
    await hub.publish(user)
    return json_response({"ok": True})


@authed
async def handle_ws(request: web.Request, user: str) -> web.StreamResponse:
    hub: PresenceHub = request.app["presence"]
    group = hub.sinks.setdefault(user, set())
    if len(group) >= MAX_SINKS_PER_USER:
        return json_response({"error": "too many sinks"}, 429)
    socket = web.WebSocketResponse(heartbeat=25, max_msg_size=4096)
    await socket.prepare(request)
    group.add(socket)
    try:
        if await hub.send(socket, sink_message(hub.payload(user))):
            async for message in socket:
                if message.type == WSMsgType.ERROR:
                    break
    finally:
        group.discard(socket)
    return socket


@authed
async def handle_poll(request: web.Request, user: str) -> web.Response:
    hub: PresenceHub = request.app["presence"]
    try:
        since = int(request.query.get("since", "-1"))
        wait = min(30.0, max(0.0, float(request.query.get("wait", "0"))))
    except ValueError:
        since, wait = -1, 0.0
    if hub.version(user) == since and wait > 0:
        condition = hub.condition(user)
        try:
            async with condition:
                await asyncio.wait_for(condition.wait_for(lambda: hub.version(user) != since), timeout=wait)
        except asyncio.TimeoutError:
            pass
    return json_response({"version": hub.version(user), "state": hub.payload(user)})


@authed
async def handle_art_upload(request: web.Request, user: str) -> web.Response:
    art: ArtStore = request.app["art"]
    kind = ART_TYPES.get(request.content_type)
    if kind is None:
        return json_response({"error": "jpeg or png only"}, 415)
    extension, magic = kind
    if request.content_length is not None and request.content_length > MAX_ART_BYTES:
        return json_response({"error": "bad size"}, 413)
    wait = art.throttle(user, now_ms())
    if wait:
        return json_response({"error": "slow down"}, 429, {"Retry-After": str(wait)})
    data = await request.read()
    if not data or len(data) > MAX_ART_BYTES:
        return json_response({"error": "bad size"}, 413)
    if not data.startswith(magic):
        return json_response({"error": "not an image"}, 415)
    name = f"{hashlib.sha1(data).hexdigest()}.{extension}"
    try:
        outcome = art.put(user, name, data)
    except OSError:
        log.exception("art storage failed")
        return json_response({"error": "storage"}, 503, {"Retry-After": str(DEFAULT_RETRY_AFTER)})
    if outcome == "quota":
        return json_response({"error": "quota"}, 429)
    if outcome == "full":
        return json_response({"error": "full"}, 503, {"Retry-After": "3600"})
    return json_response({"url": f"{PUBLIC_BASE}/art/{name}"})


async def handle_art_get(request: web.Request) -> web.Response:
    name = request.match_info["name"]
    if not ART_NAME.match(name):
        return web.Response(status=404)
    art: ArtStore = request.app["art"]
    target = art.attach() / name
    try:
        body = target.read_bytes()
    except OSError:
        return web.Response(status=404)
    art.touch(target, time.time())
    kind = "image/jpeg" if name.endswith(".jpg") else "image/png"
    headers = {"Cache-Control": "public, max-age=86400", "X-Content-Type-Options": "nosniff"}
    return web.Response(body=body, content_type=kind, headers=headers)


async def sweep_once(app: web.Application) -> None:
    await app["presence"].sweep()
    art: ArtStore = app["art"]
    forget_idle(art.uploads, now_ms(), ART_RATE_WINDOW_SECONDS)
    moment = time.time()
    if moment - art.pruned_at >= ART_PRUNE_INTERVAL_SECONDS:
        art.pruned_at = moment
        art.prune(moment)


async def presence_sweeper(app: web.Application) -> None:
    while True:
        await asyncio.sleep(SWEEP_INTERVAL_SECONDS)
        try:
            await sweep_once(app)
        except Exception:
            log.exception("presence sweep failed")


def install(app: web.Application, verify=None) -> None:
    app["presence"] = PresenceHub()
    app["art"] = ArtStore()
    app["verify"] = verify or upstream_verifier(app)
    app.router.add_post("/presence", handle_update)
    app.router.add_get("/presence/ws", handle_ws)
    app.router.add_get("/presence/poll", handle_poll)
    app.router.add_post(ART_PATH, handle_art_upload)
    app.router.add_get("/art/{name}", handle_art_get)

    async def start(application: web.Application) -> None:
        timeout = aiohttp.ClientTimeout(total=UPSTREAM_TIMEOUT_SECONDS)
        application["presence_http"] = aiohttp.ClientSession(timeout=timeout)
        application["presence_sweeper"] = asyncio.create_task(presence_sweeper(application))

    async def stop(application: web.Application) -> None:
        application["presence_sweeper"].cancel()
        try:
            await application["presence_sweeper"]
        except asyncio.CancelledError:
            pass
        await application["presence_http"].close()

    app.on_startup.append(start)
    app.on_cleanup.append(stop)
