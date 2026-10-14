import asyncio
import hashlib
import os
import re
import time
from pathlib import Path

import aiohttp
from aiohttp import WSMsgType, web

SITE_ME_URL = os.environ.get("NSM_SITE_ME_URL", "https://music.nodeshift.space/api/auth/me")
PUBLIC_BASE = os.environ.get("NSM_PUBLIC_BASE", "https://music.nodeshift.space/app/bump")
ART_DIR = Path(os.environ.get("NSM_ART_DIR", "/var/lib/nsm-bump/art"))
MAX_ART_BYTES = 600_000
TOKEN_TTL_SECONDS = 300
STALE_SECONDS = 70
MAX_SINKS_PER_USER = 6
ART_NAME = re.compile(r"^[a-f0-9]{40}\.(jpg|png)$")
SITE_ID = re.compile(r"^[0-9]{1,12}$")


def now_ms() -> int:
    return int(time.time() * 1000)


def clip(value, limit: int) -> str:
    return str(value or "").strip()[:limit]


def number(value) -> int:
    try:
        return max(0, int(float(value)))
    except (TypeError, ValueError):
        return 0


class PresenceHub:
    def __init__(self) -> None:
        self.sinks: dict[str, set[web.WebSocketResponse]] = {}
        self.states: dict[str, dict] = {}
        self.tokens: dict[str, tuple[str, float]] = {}

    def clean(self, body: dict) -> dict | None:
        title = clip(body.get("title"), 128)
        if not title:
            return None
        cover = clip(body.get("cover"), 300)
        site_id = clip(body.get("site_id"), 12)
        return {
            "device": clip(body.get("device"), 64),
            "platform": clip(body.get("platform"), 16),
            "playing": bool(body.get("playing", False)),
            "title": title,
            "artist": clip(body.get("artist"), 128),
            "album": clip(body.get("album"), 128),
            "position_ms": number(body.get("position_ms")),
            "duration_ms": number(body.get("duration_ms")),
            "cover": cover if cover.startswith("https://") else "",
            "site_id": site_id if SITE_ID.match(site_id) else "",
            "ts": now_ms(),
        }

    async def broadcast(self, user: str, payload: dict) -> None:
        for sink in list(self.sinks.get(user, ())):
            if sink.closed:
                self.sinks[user].discard(sink)
                continue
            try:
                await sink.send_json(payload)
            except ConnectionError:
                self.sinks[user].discard(sink)

    def sweep_stale(self) -> list[str]:
        cutoff = time.time() * 1000 - STALE_SECONDS * 1000
        gone = [user for user, state in self.states.items() if state["ts"] < cutoff]
        for user in gone:
            del self.states[user]
        return gone


async def verify_site_token(token: str) -> str | None:
    timeout = aiohttp.ClientTimeout(total=8)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.get(SITE_ME_URL, headers={"Authorization": f"Bearer {token}"}) as response:
            if response.status != 200:
                return None
            data = await response.json()
            value = data.get("id")
            return str(value) if value is not None else None


async def identify(request: web.Request) -> str | None:
    hub: PresenceHub = request.app["presence"]
    header = request.headers.get("Authorization", "")
    token = header[7:].strip() if header.lower().startswith("bearer ") else request.query.get("token", "")
    if not token or len(token) > 4096:
        return None
    cached = hub.tokens.get(token)
    if cached and cached[1] > time.time():
        return cached[0]
    try:
        user = await request.app["verify"](token)
    except Exception:
        return None
    if user:
        if len(hub.tokens) > 5000:
            hub.tokens.clear()
        hub.tokens[token] = (user, time.time() + TOKEN_TTL_SECONDS)
    return user


def json_response(payload: dict, status: int = 200) -> web.Response:
    return web.json_response(payload, status=status, headers={"Cache-Control": "no-store"})


async def handle_update(request: web.Request) -> web.Response:
    user = await identify(request)
    if user is None:
        return json_response({"error": "unauthorized"}, 401)
    hub: PresenceHub = request.app["presence"]
    try:
        body = await request.json()
    except Exception:
        return json_response({"error": "bad json"}, 400)
    if not isinstance(body, dict):
        return json_response({"error": "bad json"}, 400)
    if body.get("stop"):
        hub.states.pop(user, None)
        await hub.broadcast(user, {"type": "clear"})
        return json_response({"ok": True})
    state = hub.clean(body)
    if state is None:
        return json_response({"error": "title required"}, 400)
    hub.states[user] = state
    await hub.broadcast(user, {"type": "presence", **state})
    return json_response({"ok": True})


async def handle_ws(request: web.Request) -> web.StreamResponse:
    user = await identify(request)
    if user is None:
        return json_response({"error": "unauthorized"}, 401)
    hub: PresenceHub = request.app["presence"]
    group = hub.sinks.setdefault(user, set())
    if len(group) >= MAX_SINKS_PER_USER:
        return json_response({"error": "too many sinks"}, 429)
    socket = web.WebSocketResponse(heartbeat=25, max_msg_size=4096)
    await socket.prepare(request)
    group.add(socket)
    current = hub.states.get(user)
    await socket.send_json({"type": "presence", **current} if current else {"type": "clear"})
    try:
        async for message in socket:
            if message.type == WSMsgType.ERROR:
                break
    finally:
        group.discard(socket)
    return socket


async def handle_art_upload(request: web.Request) -> web.Response:
    user = await identify(request)
    if user is None:
        return json_response({"error": "unauthorized"}, 401)
    kind = request.content_type
    if kind not in ("image/jpeg", "image/png"):
        return json_response({"error": "jpeg or png only"}, 415)
    data = await request.read()
    if not data or len(data) > MAX_ART_BYTES:
        return json_response({"error": "bad size"}, 413)
    digest = hashlib.sha1(data).hexdigest()
    extension = "jpg" if kind == "image/jpeg" else "png"
    ART_DIR.mkdir(parents=True, exist_ok=True)
    target = ART_DIR / f"{digest}.{extension}"
    if not target.exists():
        target.write_bytes(data)
    return json_response({"url": f"{PUBLIC_BASE}/art/{digest}.{extension}"})


async def handle_art_get(request: web.Request) -> web.Response:
    name = request.match_info["name"]
    if not ART_NAME.match(name):
        return web.Response(status=404)
    target = ART_DIR / name
    if not target.is_file():
        return web.Response(status=404)
    kind = "image/jpeg" if name.endswith(".jpg") else "image/png"
    return web.Response(body=target.read_bytes(), content_type=kind, headers={"Cache-Control": "public, max-age=86400"})


async def presence_sweeper(app: web.Application) -> None:
    hub: PresenceHub = app["presence"]
    while True:
        await asyncio.sleep(20)
        for user in hub.sweep_stale():
            await hub.broadcast(user, {"type": "clear"})


def install(app: web.Application, verify=verify_site_token) -> None:
    app["presence"] = PresenceHub()
    app["verify"] = verify
    app.router.add_post("/presence", handle_update)
    app.router.add_get("/presence/ws", handle_ws)
    app.router.add_post("/presence/art", handle_art_upload)
    app.router.add_get("/art/{name}", handle_art_get)

    async def start(application: web.Application) -> None:
        application["presence_sweeper"] = asyncio.create_task(presence_sweeper(application))

    async def stop(application: web.Application) -> None:
        application["presence_sweeper"].cancel()
        try:
            await application["presence_sweeper"]
        except asyncio.CancelledError:
            pass

    app.on_startup.append(start)
    app.on_cleanup.append(stop)
