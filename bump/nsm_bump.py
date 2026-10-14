import asyncio
import os
import re
import secrets
import time
from collections import deque
from dataclasses import dataclass, field

from aiohttp import web

BUMP_WINDOW_MS = 450
BUMP_WAIT_SECONDS = 3.5
PAIR_TTL_SECONDS = 180
MAX_PENDING = 400
MAX_PAIRS = 2000
RATE_LIMIT = 40
RATE_WINDOW_SECONDS = 60
CLOCK_SLACK_MS = 6000
CODE_PATTERN = re.compile(r"^[A-Z0-9]{4,8}$")
MAX_WAIT_SECONDS = 20


def now_ms() -> int:
    return int(time.time() * 1000)


def clean_text(value, limit: int = 40) -> str:
    return str(value or "").strip()[:limit]


def client_ip(request: web.Request) -> str:
    if request.remote in ("127.0.0.1", "::1"):
        forwarded = request.headers.get("X-Forwarded-For", "")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.remote or "unknown"


def network_key(ip: str) -> str:
    if ":" in ip:
        return ":".join(ip.split(":")[:4])
    return ".".join(ip.split(".")[:3])


@dataclass
class Bump:
    device: str
    name: str
    platform: str
    ip: str
    impact: int
    can_host: bool
    future: asyncio.Future


@dataclass
class Pair:
    pair_id: str
    host: str
    guest: str
    created: float = field(default_factory=time.time)
    code: str | None = None
    ready: asyncio.Event = field(default_factory=asyncio.Event)


class Hub:
    def __init__(self) -> None:
        self.pending: list[Bump] = []
        self.pairs: dict[str, Pair] = {}
        self.hits: dict[str, deque] = {}

    def allowed(self, ip: str) -> bool:
        moment = time.monotonic()
        window = self.hits.setdefault(ip, deque())
        while window and moment - window[0] > RATE_WINDOW_SECONDS:
            window.popleft()
        if len(window) >= RATE_LIMIT:
            return False
        window.append(moment)
        return True

    def sweep(self) -> None:
        self.pending = [bump for bump in self.pending if not bump.future.done()]
        cutoff = time.time() - PAIR_TTL_SECONDS
        for pair_id in [key for key, pair in self.pairs.items() if pair.created < cutoff]:
            del self.pairs[pair_id]
        for ip in [key for key, window in self.hits.items() if not window]:
            del self.hits[ip]

    def find_match(self, fresh: Bump) -> Bump | None:
        candidates = [
            bump
            for bump in self.pending
            if bump.device != fresh.device and not bump.future.done() and abs(bump.impact - fresh.impact) <= BUMP_WINDOW_MS
        ]
        if not candidates:
            return None
        key = network_key(fresh.ip)
        candidates.sort(key=lambda bump: (network_key(bump.ip) != key, abs(bump.impact - fresh.impact)))
        return candidates[0]

    def make_pair(self, first: Bump, second: Bump) -> tuple[Pair | None, Bump | None, Bump | None]:
        hosts = [bump for bump in (first, second) if bump.can_host]
        if not hosts:
            return None, None, None
        if len(hosts) == 1:
            host = hosts[0]
        else:
            host = min(hosts, key=lambda bump: bump.device)
        guest = second if host is first else first
        pair = Pair(pair_id=secrets.token_hex(6), host=host.device, guest=guest.device)
        self.pairs[pair.pair_id] = pair
        return pair, host, guest


def json_response(payload: dict, status: int = 200) -> web.Response:
    return web.json_response(payload, status=status, headers={"Cache-Control": "no-store"})


def outcome(pair: Pair | None, bump: Bump, peer: Bump, host: Bump | None) -> dict:
    if pair is None or host is None:
        return {"matched": True, "error": "login_required", "peer": {"name": peer.name, "platform": peer.platform}}
    return {
        "matched": True,
        "pair": pair.pair_id,
        "role": "host" if host is bump else "guest",
        "peer": {"name": peer.name, "platform": peer.platform},
    }


async def handle_time(request: web.Request) -> web.Response:
    return json_response({"now": now_ms()})


async def handle_bump(request: web.Request) -> web.Response:
    hub: Hub = request.app["hub"]
    ip = client_ip(request)
    if not hub.allowed(ip):
        return json_response({"error": "slow down"}, 429)
    try:
        body = await request.json()
    except Exception:
        return json_response({"error": "bad json"}, 400)
    if not isinstance(body, dict):
        return json_response({"error": "bad json"}, 400)
    device = clean_text(body.get("device"), 64)
    if not device:
        return json_response({"error": "device required"}, 400)
    hub.sweep()
    if len(hub.pending) >= MAX_PENDING or len(hub.pairs) >= MAX_PAIRS:
        return json_response({"error": "busy"}, 503)
    arrived = now_ms()
    try:
        impact = int(body.get("impact_ms", arrived)) + int(body.get("offset_ms", 0))
    except (TypeError, ValueError):
        impact = arrived
    if abs(impact - arrived) > CLOCK_SLACK_MS:
        impact = arrived
    for stale in [bump for bump in hub.pending if bump.device == device and not bump.future.done()]:
        stale.future.set_result({"matched": False, "reason": "replaced"})
    hub.pending = [bump for bump in hub.pending if not bump.future.done()]
    fresh = Bump(
        device=device,
        name=clean_text(body.get("name")),
        platform=clean_text(body.get("platform"), 16),
        ip=ip,
        impact=impact,
        can_host=bool(body.get("can_host", False)),
        future=asyncio.get_running_loop().create_future(),
    )
    other = hub.find_match(fresh)
    if other is not None:
        hub.pending = [bump for bump in hub.pending if bump is not other]
        pair, host, _guest = hub.make_pair(fresh, other)
        other.future.set_result(outcome(pair, other, fresh, host))
        return json_response(outcome(pair, fresh, other, host))
    hub.pending.append(fresh)
    try:
        result = await asyncio.wait_for(asyncio.shield(fresh.future), timeout=BUMP_WAIT_SECONDS)
    except asyncio.TimeoutError:
        result = fresh.future.result() if fresh.future.done() else {"matched": False, "reason": "timeout"}
    finally:
        hub.pending = [bump for bump in hub.pending if bump is not fresh]
        if not fresh.future.done():
            fresh.future.cancel()
    return json_response(result)


async def handle_publish(request: web.Request) -> web.Response:
    hub: Hub = request.app["hub"]
    pair = hub.pairs.get(request.match_info["pair"])
    if pair is None:
        return json_response({"error": "unknown pair"}, 404)
    try:
        body = await request.json()
    except Exception:
        return json_response({"error": "bad json"}, 400)
    if not isinstance(body, dict):
        return json_response({"error": "bad json"}, 400)
    device = clean_text(body.get("device"), 64)
    code = clean_text(body.get("code"), 8).upper()
    if device != pair.host:
        return json_response({"error": "not the host"}, 403)
    if not CODE_PATTERN.match(code):
        return json_response({"error": "bad code"}, 400)
    pair.code = code
    pair.ready.set()
    return json_response({"ok": True})


async def handle_fetch(request: web.Request) -> web.Response:
    hub: Hub = request.app["hub"]
    pair = hub.pairs.get(request.match_info["pair"])
    if pair is None:
        return json_response({"error": "unknown pair"}, 404)
    device = clean_text(request.query.get("device"), 64)
    if device not in (pair.host, pair.guest):
        return json_response({"error": "not in pair"}, 403)
    try:
        wait = min(MAX_WAIT_SECONDS, max(0.0, float(request.query.get("wait", "0"))))
    except ValueError:
        wait = 0.0
    if pair.code is None and wait > 0:
        try:
            await asyncio.wait_for(pair.ready.wait(), timeout=wait)
        except asyncio.TimeoutError:
            pass
    if pair.code is None:
        return web.Response(status=204, headers={"Cache-Control": "no-store"})
    return json_response({"code": pair.code})


async def sweeper(app: web.Application) -> None:
    hub: Hub = app["hub"]
    while True:
        await asyncio.sleep(30)
        hub.sweep()


async def start_background(app: web.Application) -> None:
    app["sweeper"] = asyncio.create_task(sweeper(app))


async def stop_background(app: web.Application) -> None:
    app["sweeper"].cancel()
    try:
        await app["sweeper"]
    except asyncio.CancelledError:
        pass


def make_app() -> web.Application:
    app = web.Application(client_max_size=4096)
    app["hub"] = Hub()
    app.router.add_get("/time", handle_time)
    app.router.add_post("/bump", handle_bump)
    app.router.add_post("/pair/{pair}/room", handle_publish)
    app.router.add_get("/pair/{pair}/room", handle_fetch)
    app.on_startup.append(start_background)
    app.on_cleanup.append(stop_background)
    return app


if __name__ == "__main__":
    web.run_app(
        make_app(),
        host=os.environ.get("NSM_BUMP_HOST", "127.0.0.1"),
        port=int(os.environ.get("NSM_BUMP_PORT", "8097")),
    )
