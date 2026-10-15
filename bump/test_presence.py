import asyncio
import hashlib
import os
import socket
import time
from collections import deque

import aiohttp
import pytest
from aiohttp import web
from aiohttp.test_utils import make_mocked_request

import nsm_bump
import presence


class Clock:
    def __init__(self) -> None:
        self.value = int(time.time() * 1000)

    def __call__(self) -> int:
        return self.value

    def advance(self, seconds: float) -> None:
        self.value += int(seconds * 1000)


@pytest.fixture
def clock(monkeypatch):
    ticking = Clock()
    monkeypatch.setattr(presence, "now_ms", ticking)
    return ticking


@pytest.fixture(autouse=True)
def art_dir(tmp_path, monkeypatch):
    target = tmp_path / "art"
    monkeypatch.setattr(presence, "ART_DIR", target)
    return target


async def fake_verify(token):
    return {"good-a": "1", "good-b": "2"}.get(token)


async def make_client(aiohttp_client):
    app = nsm_bump.make_app()
    app["verify"] = fake_verify
    return await aiohttp_client(app)


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def state(**extra):
    base = {"device": "d1", "platform": "ios", "playing": True, "title": "Everyday", "artist": "Jamiroquai", "album": "TWM", "position_ms": 5000, "duration_ms": 200000, "cover": "https://burmalda.savsis.xyz/covers/a.jpg", "site_id": "183"}
    base.update(extra)
    return base


def blob(size):
    return b"\xff\xd8\xff" + os.urandom(size - 3)


async def post(client, token="good-a", **extra):
    response = await client.post("/presence", json=state(**extra), headers=auth(token))
    assert response.status == 200
    return response


async def stop(client, token="good-a", **extra):
    response = await client.post("/presence", json={"stop": True, **extra}, headers=auth(token))
    assert response.status == 200
    return response


async def poll(client, token="good-a", since="-1", wait="0"):
    response = await client.get("/presence/poll", params={"since": since, "wait": wait}, headers=auth(token))
    assert response.status == 200
    return await response.json()


async def upload(client, token, data, kind="image/jpeg"):
    return await client.post("/presence/art", data=data, headers={**auth(token), "Content-Type": kind})


async def test_requires_token(aiohttp_client):
    client = await make_client(aiohttp_client)
    assert (await client.post("/presence", json=state())).status == 401
    assert (await client.post("/presence", json=state(), headers=auth("nope"))).status == 401
    assert (await client.get("/presence/ws")).status == 401
    assert (await client.get("/presence/poll")).status == 401
    assert (await client.post("/presence/art", data=b"x", headers={"Content-Type": "image/jpeg"})).status == 401


async def test_query_token_is_not_accepted(aiohttp_client):
    client = await make_client(aiohttp_client)
    with pytest.raises(aiohttp.WSServerHandshakeError) as refused:
        await client.ws_connect("/presence/ws?token=good-a")
    assert refused.value.status == 401
    assert (await client.get("/presence/poll?token=good-a")).status == 401
    assert (await client.post("/presence?token=good-a", json=state())).status == 401


async def test_update_reaches_sink_of_same_user_only(aiohttp_client):
    client = await make_client(aiohttp_client)
    mine = await client.ws_connect("/presence/ws", headers=auth("good-a"))
    other = await client.ws_connect("/presence/ws", headers=auth("good-b"))
    assert (await mine.receive_json())["type"] == "clear"
    assert (await other.receive_json())["type"] == "clear"
    await post(client)
    message = await mine.receive_json(timeout=3)
    assert message["type"] == "presence"
    assert message["title"] == "Everyday"
    assert message["site_id"] == "183"
    assert message["device"] == "d1"
    assert message["ts"] > 0
    assert message["age_ms"] >= 0
    assert "seen" not in message and "since" not in message
    with pytest.raises(asyncio.TimeoutError):
        await other.receive_json(timeout=0.4)


async def test_new_sink_gets_current_state(aiohttp_client):
    client = await make_client(aiohttp_client)
    await post(client)
    sink = await client.ws_connect("/presence/ws", headers=auth("good-a"))
    message = await sink.receive_json()
    assert message["type"] == "presence"
    assert message["artist"] == "Jamiroquai"
    assert "age_ms" in message


async def test_stop_with_device_clears(aiohttp_client):
    client = await make_client(aiohttp_client)
    sink = await client.ws_connect("/presence/ws", headers=auth("good-a"))
    await sink.receive_json()
    await post(client)
    await sink.receive_json()
    await stop(client, device="d1")
    assert (await sink.receive_json())["type"] == "clear"
    assert (await poll(client))["state"] is None


async def test_stop_removes_only_that_device(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, device="phone", title="PhoneSong")
    clock.advance(2)
    await post(client, device="pc", title="PcSong")
    assert (await poll(client))["state"]["device"] == "pc"
    await stop(client, device="pc")
    body = await poll(client)
    assert body["state"]["device"] == "phone"
    assert body["state"]["title"] == "PhoneSong"
    await stop(client, device="phone")
    assert (await poll(client))["state"] is None


async def test_stop_without_device_clears_every_slot(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, device="phone")
    clock.advance(1)
    await post(client, device="pc", title="Other")
    await stop(client)
    assert (await poll(client))["state"] is None
    assert client.app["presence"].states == {}


async def test_stop_for_unknown_device_changes_nothing(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, device="phone")
    before = await poll(client)
    await stop(client, device="ghost")
    after = await poll(client)
    assert after["version"] == before["version"]
    assert after["state"]["device"] == "phone"


async def test_paused_pc_does_not_override_playing_phone(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, device="phone", title="PhoneSong")
    before = await poll(client)
    clock.advance(3)
    await post(client, device="pc", title="PcSong", playing=False)
    after = await poll(client)
    assert after["state"]["title"] == "PhoneSong"
    assert after["state"]["device"] == "phone"
    assert after["version"] == before["version"]


async def test_playing_device_wins_over_newer_paused_one(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, device="pc", title="PcSong", playing=False)
    clock.advance(1)
    await post(client, device="phone", title="PhoneSong")
    clock.advance(1)
    await post(client, device="tablet", title="TabletSong", playing=False)
    assert (await poll(client))["state"]["device"] == "phone"


async def test_newest_paused_slot_is_chosen_when_nothing_plays(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, device="phone", title="Old", playing=False)
    clock.advance(5)
    await post(client, device="pc", title="New", playing=False)
    body = await poll(client)
    assert body["state"]["device"] == "pc"
    assert body["state"]["playing"] is False


async def test_two_playing_devices_do_not_flap(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    phone_started = clock.value
    await post(client, device="phone", title="A", position_ms=5000)
    clock.advance(1)
    pc_started = clock.value
    await post(client, device="pc", title="B", position_ms=0)
    first = await poll(client)
    assert first["state"]["device"] == "pc"
    for _ in range(4):
        clock.advance(15)
        await post(client, device="phone", title="A", position_ms=5000 + clock.value - phone_started)
        await post(client, device="pc", title="B", position_ms=clock.value - pc_started)
        current = await poll(client)
        assert current["state"]["device"] == "pc"
        assert current["version"] == first["version"]
    assert hub.states["1"]["phone"]["since"] == phone_started
    clock.advance(2)
    await post(client, device="phone", title="C", position_ms=0)
    switched = await poll(client)
    assert switched["state"]["device"] == "phone"
    assert switched["state"]["title"] == "C"
    assert switched["version"] == first["version"] + 1


async def test_heartbeat_keeps_anchor_and_version(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, position_ms=5000)
    first = await poll(client)
    clock.advance(15)
    await post(client, position_ms=20_400)
    body = await poll(client)
    assert body["version"] == first["version"]
    assert body["state"]["position_ms"] == 5000
    assert body["state"]["age_ms"] == 15_000
    assert body["state"]["ts"] == first["state"]["ts"]


async def test_position_jump_threshold(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, position_ms=5000)
    first = await poll(client)
    clock.advance(10)
    await post(client, position_ms=5000 + 10_000 + 2500)
    inside = await poll(client)
    assert inside["version"] == first["version"]
    assert inside["state"]["position_ms"] == 5000
    await post(client, position_ms=5000 + 10_000 + 2501)
    outside = await poll(client)
    assert outside["version"] == first["version"] + 1
    assert outside["state"]["position_ms"] == 17_501
    assert outside["state"]["age_ms"] == 0


async def test_backward_seek_bumps_version(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, position_ms=60_000)
    first = await poll(client)
    clock.advance(5)
    await post(client, position_ms=1000)
    body = await poll(client)
    assert body["version"] == first["version"] + 1
    assert body["state"]["position_ms"] == 1000


async def test_pause_and_resume_bump_and_reset_since(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    await post(client, position_ms=5000)
    first = await poll(client)
    clock.advance(10)
    await post(client, playing=False, position_ms=15_000)
    paused = await poll(client)
    assert paused["version"] == first["version"] + 1
    assert paused["state"]["playing"] is False
    assert hub.states["1"]["d1"]["since"] == clock.value
    paused_at = clock.value
    clock.advance(30)
    await post(client, playing=False, position_ms=15_000)
    assert (await poll(client))["version"] == paused["version"]
    assert hub.states["1"]["d1"]["since"] == paused_at
    clock.advance(5)
    await post(client, playing=True, position_ms=15_000)
    resumed = await poll(client)
    assert resumed["version"] == paused["version"] + 1
    assert resumed["state"]["playing"] is True


async def test_cover_arriving_later_bumps_version(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, cover="")
    first = await poll(client)
    clock.advance(1)
    await post(client, cover="https://burmalda.savsis.xyz/covers/b.png", position_ms=6000)
    body = await poll(client)
    assert body["version"] == first["version"] + 1
    assert body["state"]["cover"].endswith("b.png")


async def test_playing_slot_expires_without_heartbeat(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    await post(client)
    clock.advance(69)
    assert hub.expire() == []
    clock.advance(2)
    assert hub.expire() == ["1"]
    assert "1" not in hub.states


async def test_heartbeat_refreshes_expiry(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    await post(client)
    clock.advance(60)
    await post(client, position_ms=65_000)
    clock.advance(60)
    assert hub.expire() == []
    clock.advance(11)
    assert hub.expire() == ["1"]


async def test_paused_slot_survives_until_paused_ttl(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    await post(client, playing=False)
    clock.advance(600)
    assert hub.expire() == []
    clock.advance(presence.PAUSED_TTL_SECONDS - 599)
    assert hub.expire() == ["1"]


async def test_paused_ttl_is_configurable(aiohttp_client, clock, monkeypatch):
    monkeypatch.setattr(presence, "PAUSED_TTL_SECONDS", 90)
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    await post(client, playing=False)
    clock.advance(89)
    assert hub.expire() == []
    clock.advance(2)
    assert hub.expire() == ["1"]


def test_env_int(monkeypatch):
    monkeypatch.delenv("NSM_TEST_VALUE", raising=False)
    assert presence.env_int("NSM_TEST_VALUE", 1200) == 1200
    monkeypatch.setenv("NSM_TEST_VALUE", "45")
    assert presence.env_int("NSM_TEST_VALUE", 1200) == 45
    monkeypatch.setenv("NSM_TEST_VALUE", "soon")
    assert presence.env_int("NSM_TEST_VALUE", 1200) == 1200


def test_default_ttls():
    assert presence.PLAYING_TTL_SECONDS == 70
    assert presence.PAUSED_TTL_SECONDS == presence.env_int("NSM_PAUSED_TTL_SECONDS", 1200)


async def test_sweep_expires_one_slot_and_falls_back_to_other(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    await post(client, device="phone", title="PhoneSong", playing=False)
    clock.advance(1)
    await post(client, device="pc", title="PcSong")
    assert (await poll(client))["state"]["device"] == "pc"
    version = (await poll(client))["version"]
    clock.advance(100)
    await hub.sweep()
    body = await poll(client)
    assert body["state"]["device"] == "phone"
    assert body["version"] == version + 1


async def test_sweep_clears_sink_and_bumps_version(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    sink = await client.ws_connect("/presence/ws", headers=auth("good-a"))
    await sink.receive_json()
    await post(client)
    await sink.receive_json()
    version = (await poll(client))["version"]
    clock.advance(71)
    await hub.sweep()
    assert (await sink.receive_json(timeout=3))["type"] == "clear"
    body = await poll(client)
    assert body["state"] is None
    assert body["version"] == version + 1


async def test_version_starts_at_boot_epoch(aiohttp_client):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    assert abs(hub.epoch - int(time.time())) <= 2
    assert (await poll(client))["version"] == hub.epoch
    await post(client)
    assert (await poll(client))["version"] == hub.epoch + 1


async def test_restarted_hub_never_reports_lower_version():
    old = presence.PresenceHub(epoch=1000)
    for index in range(3):
        slot = old.clean(state(title=f"T{index}"), 5000 + index)
        old.store("1", slot, 5000 + index)
        await old.publish("1")
    assert old.version("1") == 1003
    restarted = presence.PresenceHub(epoch=1010)
    assert restarted.version("1") > old.version("1")
    assert restarted.version("other") == 1010


async def test_poll_carries_device_and_age(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    await post(client, device="phone")
    clock.advance(4)
    body = await poll(client)
    assert body["state"]["device"] == "phone"
    assert body["state"]["age_ms"] == 4000
    assert body["state"]["position_ms"] == 5000
    assert "seen" not in body["state"] and "since" not in body["state"]
    clock.advance(1)
    assert (await poll(client))["state"]["age_ms"] == 5000


async def test_poll_returns_immediately_when_version_differs(aiohttp_client):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    await post(client)
    response = await client.get("/presence/poll", params={"since": "0", "wait": "5"}, headers=auth("good-a"))
    body = await response.json()
    assert body["version"] == hub.epoch + 1
    assert body["state"]["title"] == "Everyday"


async def test_poll_waits_for_change(aiohttp_client):
    client = await make_client(aiohttp_client)
    first = await poll(client)
    waiting = asyncio.ensure_future(client.get("/presence/poll", params={"since": str(first["version"]), "wait": "5"}, headers=auth("good-a")))
    await asyncio.sleep(0.2)
    await post(client, title="Later")
    body = await (await waiting).json()
    assert body["state"]["title"] == "Later"


async def test_poll_ignores_identical_heartbeats(aiohttp_client):
    client = await make_client(aiohttp_client)
    await post(client)
    first = await poll(client)
    waiting = asyncio.ensure_future(client.get("/presence/poll", params={"since": str(first["version"]), "wait": "5"}, headers=auth("good-a")))
    await asyncio.sleep(0.1)
    await post(client)
    done, _ = await asyncio.wait({waiting}, timeout=0.4)
    assert not done
    await post(client, title="Changed")
    body = await (await waiting).json()
    assert body["state"]["title"] == "Changed"
    assert body["version"] == first["version"] + 1


async def test_poll_times_out_with_same_version(aiohttp_client):
    client = await make_client(aiohttp_client)
    first = await poll(client)
    body = await poll(client, since=str(first["version"]), wait="0.3")
    assert body["version"] == first["version"]
    assert body["state"] is None


async def test_cleaning(aiohttp_client):
    client = await make_client(aiohttp_client)
    await post(client, cover="http://insecure/x.jpg", site_id="abc", title="x" * 500)
    message = (await poll(client))["state"]
    assert message["cover"] == ""
    assert message["site_id"] == ""
    assert len(message["title"]) == 128
    assert (await client.post("/presence", json={"title": ""}, headers=auth("good-a"))).status == 400
    assert (await client.post("/presence", data="[1]", headers={**auth("good-a"), "Content-Type": "application/json"})).status == 400
    assert (await client.post("/presence", data="nope", headers={**auth("good-a"), "Content-Type": "application/json"})).status == 400


@pytest.mark.parametrize(
    "cover,kept",
    [
        ("https://burmalda.savsis.xyz/covers/a.jpg", True),
        ("https://music.nodeshift.space/app/bump/art/" + "a" * 40 + ".jpg", True),
        ("https://burmalda.savsis.xyz:443/covers/a.jpg", True),
        ("http://burmalda.savsis.xyz/covers/a.jpg", False),
        ("https://evil.example/covers/a.jpg", False),
        ("https://burmalda.savsis.xyz@evil.example/a.jpg", False),
        ("https://user:pass@burmalda.savsis.xyz/a.jpg", False),
        ("https://burmalda.savsis.xyz:8443/a.jpg", False),
        ("https://burmalda.savsis.xyz/a b.jpg", False),
        ("ftp://burmalda.savsis.xyz/a.jpg", False),
        ("", False),
    ],
)
def test_cover_rules(cover, kept):
    assert presence.cover_url(cover) == (cover if kept else "")


def test_cover_is_dropped_not_clipped_when_too_long():
    prefix = "https://burmalda.savsis.xyz/covers/"
    exact = prefix + "a" * (presence.COVER_LIMIT - len(prefix))
    assert len(exact) == presence.COVER_LIMIT
    assert presence.cover_url(exact) == exact
    assert presence.cover_url(exact + "a") == ""
    assert presence.cover_url(prefix + "%D0%90" * 80) == ""


async def test_garbage_numbers_do_not_crash(aiohttp_client):
    client = await make_client(aiohttp_client)
    raw = '{"title": "x", "device": "d1", "playing": "false", "position_ms": 1e999, "duration_ms": 1e30}'
    response = await client.post("/presence", data=raw, headers={**auth("good-a"), "Content-Type": "application/json"})
    assert response.status == 200
    body = (await poll(client))["state"]
    assert body["playing"] is False
    assert body["position_ms"] == 0
    assert body["duration_ms"] == presence.MAX_TIME_MS


async def test_position_is_clamped_to_duration(aiohttp_client):
    client = await make_client(aiohttp_client)
    await post(client, position_ms=10 ** 30, duration_ms=3000)
    body = (await poll(client))["state"]
    assert body["position_ms"] == 3000
    assert body["duration_ms"] == 3000


async def test_playing_must_be_a_real_boolean(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    for index, value in enumerate(["true", 1, "yes", None]):
        await post(client, device=f"d{index}", playing=value)
    assert all(slot["playing"] is False for slot in client.app["presence"].states["1"].values())
    await post(client, device="real", playing=True)
    assert (await poll(client))["state"]["device"] == "real"


async def test_device_slots_are_capped(aiohttp_client, clock, monkeypatch):
    monkeypatch.setattr(presence, "MAX_DEVICES_PER_USER", 2)
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    for name in ("one", "two", "three"):
        await post(client, device=name, title=name, playing=False)
        clock.advance(1)
    assert sorted(hub.states["1"]) == ["three", "two"]


async def test_art_upload_and_fetch(aiohttp_client):
    client = await make_client(aiohttp_client)
    data = b"\xff\xd8\xff" + b"0" * 100
    response = await upload(client, "good-a", data)
    assert response.status == 200
    url = (await response.json())["url"]
    assert url.startswith(presence.PUBLIC_BASE + "/art/")
    name = url.rsplit("/", 1)[1]
    fetched = await client.get(f"/art/{name}")
    assert fetched.status == 200
    assert await fetched.read() == data
    assert fetched.headers["Content-Type"] == "image/jpeg"
    assert fetched.headers["X-Content-Type-Options"] == "nosniff"
    assert (await client.get("/art/../etc.jpg")).status == 404
    assert (await client.get("/art/" + "0" * 40 + ".jpg")).status == 404


@pytest.mark.parametrize("size", [200_000, 599_999, 600_000, 700_000])
async def test_art_accepts_realistic_jpeg_sizes(aiohttp_client, size):
    client = await make_client(aiohttp_client)
    data = blob(size)
    response = await upload(client, "good-a", data)
    assert response.status == 200
    name = (await response.json())["url"].rsplit("/", 1)[1]
    fetched = await client.get(f"/art/{name}")
    assert await fetched.read() == data


@pytest.mark.parametrize("size", [700_001, 800_000, 3_000_000])
async def test_art_rejects_oversize(aiohttp_client, size):
    client = await make_client(aiohttp_client)
    assert (await upload(client, "good-a", blob(size))).status == 413


async def test_art_size_is_checked_before_reading(aiohttp_client, monkeypatch):
    app = web.Application(client_max_size=5_000_000)
    presence.install(app, verify=fake_verify)
    client = await aiohttp_client(app)

    async def refuse(self):
        raise AssertionError("body was read")

    monkeypatch.setattr(web.BaseRequest, "read", refuse)
    assert (await upload(client, "good-a", blob(700_001))).status == 413


async def test_art_body_over_the_limit_is_rejected_after_reading_when_length_is_unknown(aiohttp_client):
    app = web.Application(client_max_size=5_000_000)
    presence.install(app, verify=fake_verify)
    client = await aiohttp_client(app)

    async def chunks():
        yield b"\xff\xd8\xff"
        yield b"0" * 700_000

    response = await client.post("/presence/art", data=chunks(), headers={**auth("good-a"), "Content-Type": "image/jpeg"})
    assert response.status == 413
    assert not presence.ART_DIR.exists()


async def test_art_rejects_empty_body_and_wrong_type(aiohttp_client):
    client = await make_client(aiohttp_client)
    assert (await upload(client, "good-a", b"")).status == 413
    assert (await upload(client, "good-a", b"x", kind="text/plain")).status == 415


async def test_art_checks_magic_bytes(aiohttp_client):
    client = await make_client(aiohttp_client)
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 50
    assert (await upload(client, "good-a", b"<html>not an image</html>")).status == 415
    assert (await upload(client, "good-a", png)).status == 415
    assert (await upload(client, "good-a", blob(100), kind="image/png")).status == 415
    accepted = await upload(client, "good-a", png, kind="image/png")
    assert accepted.status == 200
    assert (await accepted.json())["url"].endswith(".png")


async def test_art_same_content_is_stored_once(aiohttp_client, art_dir):
    client = await make_client(aiohttp_client)
    data = blob(1000)
    first = await (await upload(client, "good-a", data)).json()
    second = await (await upload(client, "good-b", data)).json()
    assert first == second
    assert len([path for path in art_dir.iterdir() if path.suffix == ".jpg"]) == 1


async def test_art_write_is_atomic(aiohttp_client, art_dir, monkeypatch):
    client = await make_client(aiohttp_client)
    data = blob(5000)
    real = os.replace

    def broken(source, target):
        raise OSError("disk went away")

    monkeypatch.setattr(os, "replace", broken)
    response = await upload(client, "good-a", data)
    monkeypatch.setattr(os, "replace", real)
    assert response.status == 503
    assert response.headers["Retry-After"]
    assert list(art_dir.iterdir()) == []
    retry = await upload(client, "good-a", data)
    assert retry.status == 200
    name = (await retry.json())["url"].rsplit("/", 1)[1]
    assert (art_dir / name).read_bytes() == data
    assert not [path for path in art_dir.iterdir() if path.name.endswith(".tmp")]


async def test_art_per_user_file_quota_evicts_the_oldest(aiohttp_client, art_dir, monkeypatch):
    monkeypatch.setattr(presence, "ART_USER_MAX_FILES", 2)
    client = await make_client(aiohttp_client)
    first, second, third = blob(500), blob(500), blob(500)
    assert (await upload(client, "good-a", first)).status == 200
    assert (await upload(client, "good-a", second)).status == 200
    assert (await upload(client, "good-a", third)).status == 200
    assert len([path for path in art_dir.iterdir() if path.suffix == ".jpg"]) == 2
    assert (await upload(client, "good-a", first)).status == 200
    assert (await upload(client, "good-b", third)).status == 200


async def test_art_eviction_keeps_files_other_users_still_own(aiohttp_client, art_dir, monkeypatch):
    monkeypatch.setattr(presence, "ART_USER_MAX_FILES", 1)
    client = await make_client(aiohttp_client)
    shared, other = blob(500), blob(500)
    assert (await upload(client, "good-a", shared)).status == 200
    assert (await upload(client, "good-b", shared)).status == 200
    assert (await upload(client, "good-a", other)).status == 200
    assert len([path for path in art_dir.iterdir() if path.suffix == ".jpg"]) == 2


async def test_art_per_user_byte_quota(aiohttp_client, monkeypatch):
    monkeypatch.setattr(presence, "ART_USER_MAX_BYTES", 1000)
    client = await make_client(aiohttp_client)
    assert (await upload(client, "good-a", blob(600))).status == 200
    assert (await upload(client, "good-a", blob(600))).status == 200
    assert (await upload(client, "good-a", blob(400))).status == 200
    refused = await upload(client, "good-a", blob(1200))
    assert refused.status == 429
    assert (await refused.json())["error"] == "quota"


async def test_art_rate_limit(aiohttp_client, clock, monkeypatch):
    monkeypatch.setattr(presence, "ART_RATE_LIMIT", 3)
    client = await make_client(aiohttp_client)
    for _ in range(3):
        assert (await upload(client, "good-a", blob(200))).status == 200
    limited = await upload(client, "good-a", blob(200))
    assert limited.status == 429
    assert 1 <= int(limited.headers["Retry-After"]) <= presence.ART_RATE_WINDOW_SECONDS
    assert (await upload(client, "good-b", blob(200))).status == 200
    clock.advance(presence.ART_RATE_WINDOW_SECONDS + 1)
    assert (await upload(client, "good-a", blob(200))).status == 200


async def test_art_global_cap(aiohttp_client, monkeypatch):
    monkeypatch.setattr(presence, "ART_TOTAL_MAX_BYTES", 1500)
    client = await make_client(aiohttp_client)
    first = blob(1000)
    assert (await upload(client, "good-a", first)).status == 200
    full = await upload(client, "good-b", blob(1000))
    assert full.status == 503
    assert full.headers["Retry-After"]
    assert (await upload(client, "good-b", first)).status == 200


async def test_art_index_survives_restart(aiohttp_client, art_dir, monkeypatch):
    monkeypatch.setattr(presence, "ART_USER_MAX_FILES", 2)
    first = await make_client(aiohttp_client)
    assert (await upload(first, "good-a", blob(300))).status == 200
    assert (await upload(first, "good-a", blob(300))).status == 200
    leftover = art_dir / ".half.jpg.abc123.tmp"
    leftover.write_bytes(b"partial")
    second = await make_client(aiohttp_client)
    assert (await upload(second, "good-a", blob(300))).status == 200
    assert len([path for path in art_dir.iterdir() if path.suffix == ".jpg"]) == 2
    assert (await upload(second, "good-b", blob(300))).status == 200
    assert len([path for path in art_dir.iterdir() if path.suffix == ".jpg"]) == 3
    assert not leftover.exists()


async def test_art_fetch_touches_and_sweep_prunes_idle_files(aiohttp_client, art_dir):
    client = await make_client(aiohttp_client)
    idle = (await (await upload(client, "good-a", blob(300))).json())["url"].rsplit("/", 1)[1]
    used = (await (await upload(client, "good-a", blob(300))).json())["url"].rsplit("/", 1)[1]
    now = time.time()
    os.utime(art_dir / idle, (now - 100 * 86400, now - 100 * 86400))
    os.utime(art_dir / used, (now - 2 * 86400, now - 2 * 86400))
    assert (await client.get(f"/art/{used}")).status == 200
    assert time.time() - (art_dir / used).stat().st_mtime < 3600
    await presence.sweep_once(client.app)
    assert not (art_dir / idle).exists()
    assert (art_dir / used).exists()
    assert (await client.get(f"/art/{idle}")).status == 404
    assert client.app["art"].owners["1"] == {used}
    assert (await client.get(f"/art/{used}")).status == 200


async def test_json_routes_reject_big_bodies(aiohttp_client):
    client = await make_client(aiohttp_client)
    assert (await client.post("/presence", json={"title": "x" * 5000}, headers=auth("good-a"))).status == 413
    assert (await client.post("/bump", json={"device": "x" * 5000})).status == 413
    assert (await client.post("/presence", json=state(), headers=auth("good-a"))).status == 200


async def test_sweeper_survives_errors(aiohttp_client, monkeypatch):
    calls = []

    async def flaky(app):
        calls.append(1)
        if len(calls) == 1:
            raise RuntimeError("boom")

    monkeypatch.setattr(presence, "sweep_once", flaky)
    monkeypatch.setattr(presence, "SWEEP_INTERVAL_SECONDS", 0.01)
    client = await make_client(aiohttp_client)
    await asyncio.sleep(0.3)
    assert len(calls) >= 2
    assert not client.app["presence_sweeper"].done()


class FakeSink:
    closed = False

    def __init__(self, behaviour="ok"):
        self.behaviour = behaviour
        self.sent = []

    async def send_json(self, message):
        if self.behaviour == "raise":
            raise RuntimeError("socket exploded")
        if self.behaviour == "hang":
            await asyncio.sleep(30)
        self.sent.append(message)


async def test_broken_sinks_are_dropped_without_blocking_others(monkeypatch):
    monkeypatch.setattr(presence, "SINK_SEND_TIMEOUT_SECONDS", 0.05)
    hub = presence.PresenceHub()
    good, broken, hung = FakeSink(), FakeSink("raise"), FakeSink("hang")
    hub.sinks["1"] = {good, broken, hung}
    hub.store("1", hub.clean(state()))
    assert await hub.publish("1") is True
    assert good.sent and good.sent[0]["type"] == "presence"
    assert hub.sinks["1"] == {good}


async def upstream_client(aiohttp_client, aiohttp_server, monkeypatch, answer):
    hits = []

    async def me(request):
        hits.append(request.headers.get("Authorization"))
        return await answer(request)

    upstream = web.Application()
    upstream.router.add_get("/api/auth/me", me)
    server = await aiohttp_server(upstream)
    monkeypatch.setattr(presence, "SITE_ME_URL", str(server.make_url("/api/auth/me")))
    client = await aiohttp_client(nsm_bump.make_app())
    return client, hits


async def good_user(request):
    return web.json_response({"id": 7})


def answering(code, **headers):
    async def answer(request):
        return web.Response(status=code, headers=headers)

    return answer


async def test_site_token_is_verified_and_cached(aiohttp_client, aiohttp_server, monkeypatch, clock):
    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, good_user)
    for _ in range(3):
        await post(client, "token-one")
    assert hits == ["Bearer token-one"]
    assert "7" in client.app["presence"].states
    clock.advance(presence.TOKEN_TTL_SECONDS + 1)
    await post(client, "token-one")
    assert len(hits) == 2


async def test_denied_token_is_cached_negatively(aiohttp_client, aiohttp_server, monkeypatch, clock):
    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, answering(401))
    hub = client.app["presence"]
    for _ in range(3):
        assert (await client.post("/presence", json=state(), headers=auth("bad-token"))).status == 401
    assert len(hits) == 1
    key = hashlib.sha256(b"bad-token").hexdigest()
    assert key in hub.denied
    assert "bad-token" not in hub.denied and "bad-token" not in hub.tokens
    clock.advance(presence.DENIED_TTL_SECONDS + 1)
    assert (await client.post("/presence", json=state(), headers=auth("bad-token"))).status == 401
    assert len(hits) == 2
    assert (await client.post("/presence", json=state(), headers=auth("another-bad"))).status == 401
    assert len(hits) == 3


async def test_forbidden_upstream_counts_as_denied(aiohttp_client, aiohttp_server, monkeypatch):
    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, answering(403))
    assert (await client.post("/presence", json=state(), headers=auth("t"))).status == 401


async def test_upstream_without_user_id_is_unauthorized(aiohttp_client, aiohttp_server, monkeypatch):
    async def nobody(request):
        return web.json_response({"name": "anon"})

    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, nobody)
    assert (await client.post("/presence", json=state(), headers=auth("t"))).status == 401


@pytest.mark.parametrize("code,retry,expected", [(500, None, "5"), (502, None, "5"), (503, None, "5"), (429, "7", "7"), (429, None, "5"), (404, None, "5")])
async def test_upstream_trouble_is_503_with_retry_after(aiohttp_client, aiohttp_server, monkeypatch, code, retry, expected):
    headers = {"Retry-After": retry} if retry else {}
    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, answering(code, **headers))
    for attempt in range(2):
        response = await client.post("/presence", json=state(), headers=auth("t"))
        assert response.status == 503
        assert response.headers["Retry-After"] == expected
        assert (await response.json())["error"] == "unavailable"
    assert len(hits) == 2
    assert client.app["presence"].denied == {}


async def test_upstream_garbage_is_503(aiohttp_client, aiohttp_server, monkeypatch):
    async def html(request):
        return web.Response(text="<html>challenge</html>", content_type="text/html")

    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, html)
    assert (await client.post("/presence", json=state(), headers=auth("t"))).status == 503

    async def listing(request):
        return web.json_response([1, 2])

    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, listing)
    assert (await client.post("/presence", json=state(), headers=auth("t"))).status == 503


async def test_unreachable_upstream_is_503(aiohttp_client, monkeypatch):
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    monkeypatch.setattr(presence, "SITE_ME_URL", f"http://127.0.0.1:{port}/api/auth/me")
    client = await aiohttp_client(nsm_bump.make_app())
    response = await client.post("/presence", json=state(), headers=auth("t"))
    assert response.status == 503
    assert response.headers["Retry-After"] == "5"
    assert (await client.get("/presence/poll", headers=auth("t"))).status == 503


async def test_slow_upstream_times_out_as_503(aiohttp_client, aiohttp_server, monkeypatch):
    async def slow(request):
        await asyncio.sleep(2)
        return web.json_response({"id": 1})

    monkeypatch.setattr(presence, "UPSTREAM_TIMEOUT_SECONDS", 0.2)
    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, slow)
    assert (await client.post("/presence", json=state(), headers=auth("t"))).status == 503


async def test_verifier_crash_is_503_not_401(aiohttp_client):
    async def crashing(token):
        raise ValueError("bug")

    app = nsm_bump.make_app()
    app["verify"] = crashing
    client = await aiohttp_client(app)
    response = await client.post("/presence", json=state(), headers=auth("t"))
    assert response.status == 503
    assert response.headers["Retry-After"] == "5"


def counting_verifier():
    calls = []

    async def verify(token):
        calls.append(token)
        return {"good-a": "1"}.get(token)

    return verify, calls


async def forwarded_post(client, token, address):
    return await client.post("/presence", json=state(), headers={**auth(token), "X-Forwarded-For": address})


async def test_uncached_verifications_are_limited_per_ip(aiohttp_client, clock, monkeypatch):
    monkeypatch.setattr(presence, "VERIFY_RATE_LIMIT", 3)
    verify, calls = counting_verifier()
    app = nsm_bump.make_app()
    app["verify"] = verify
    client = await aiohttp_client(app)
    for index in range(3):
        assert (await forwarded_post(client, f"junk-{index}", "203.0.113.5")).status == 401
    blocked = await forwarded_post(client, "junk-3", "203.0.113.5")
    assert blocked.status == 429
    assert 1 <= int(blocked.headers["Retry-After"]) <= presence.VERIFY_RATE_WINDOW_SECONDS
    assert (await blocked.json())["error"] == "slow down"
    assert len(calls) == 3
    assert (await forwarded_post(client, "junk-4", "203.0.113.6")).status == 401
    assert len(calls) == 4
    clock.advance(presence.VERIFY_RATE_WINDOW_SECONDS + 1)
    assert (await forwarded_post(client, "junk-5", "203.0.113.5")).status == 401


async def test_cached_tokens_skip_the_verification_limit(aiohttp_client, monkeypatch):
    monkeypatch.setattr(presence, "VERIFY_RATE_LIMIT", 1)
    verify, calls = counting_verifier()
    app = nsm_bump.make_app()
    app["verify"] = verify
    client = await aiohttp_client(app)
    for _ in range(6):
        assert (await forwarded_post(client, "good-a", "203.0.113.5")).status == 200
    assert calls == ["good-a"]
    assert (await forwarded_post(client, "junk", "203.0.113.5")).status == 429
    assert (await forwarded_post(client, "good-a", "203.0.113.5")).status == 200


async def test_denied_tokens_skip_the_verification_limit(aiohttp_client, monkeypatch):
    monkeypatch.setattr(presence, "VERIFY_RATE_LIMIT", 1)
    verify, calls = counting_verifier()
    app = nsm_bump.make_app()
    app["verify"] = verify
    client = await aiohttp_client(app)
    for _ in range(4):
        assert (await forwarded_post(client, "junk", "203.0.113.5")).status == 401
    assert calls == ["junk"]


async def test_sweep_forgets_idle_rate_windows(aiohttp_client, clock):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    assert (await forwarded_post(client, "junk", "203.0.113.5")).status == 401
    assert (await upload(client, "good-a", blob(300))).status == 200
    assert "203.0.113.5" in hub.verifications or "127.0.0.1" in hub.verifications
    assert client.app["art"].uploads
    clock.advance(max(presence.VERIFY_RATE_WINDOW_SECONDS, presence.ART_RATE_WINDOW_SECONDS) + 1)
    await presence.sweep_once(client.app)
    assert hub.verifications == {}
    assert client.app["art"].uploads == {}


def test_throttle_counts_a_sliding_window():
    windows = {}
    assert [presence.throttle(windows, "k", 1000 * second, 2, 10) for second in (0, 1, 2)] == [0, 0, 8]
    assert presence.throttle(windows, "k", 10_000, 2, 10) == 0
    assert presence.throttle(windows, "k", 10_500, 2, 10) == 1
    assert presence.throttle(windows, "k", 11_000, 2, 10) == 0
    assert presence.throttle(windows, "other", 11_000, 2, 10) == 0


def test_forget_idle_keeps_recent_windows():
    windows = {}
    presence.throttle(windows, "old", 0, 5, 10)
    presence.throttle(windows, "new", 9000, 5, 10)
    windows["empty"] = deque()
    presence.forget_idle(windows, 10_000, 10)
    assert list(windows) == ["new"]


class Peer:
    def __init__(self, host):
        self.host = host

    def get_extra_info(self, name, default=None):
        return (self.host, 4000) if name == "peername" else default

    def is_closing(self):
        return False


@pytest.mark.parametrize(
    "remote,forwarded,expected",
    [
        ("127.0.0.1", "198.51.100.7, 10.0.0.1", "198.51.100.7"),
        ("::1", "198.51.100.7", "198.51.100.7"),
        ("127.0.0.1", "", "127.0.0.1"),
        ("203.0.113.9", "198.51.100.7", "203.0.113.9"),
    ],
)
def test_client_ip_trusts_forwarding_only_from_loopback(remote, forwarded, expected):
    headers = {"X-Forwarded-For": forwarded} if forwarded else {}
    request = make_mocked_request("POST", "/presence", headers=headers, transport=Peer(remote))
    assert presence.client_ip(request) == expected


async def test_one_shared_session_is_closed_on_cleanup(aiohttp_client, aiohttp_server, monkeypatch):
    client, hits = await upstream_client(aiohttp_client, aiohttp_server, monkeypatch, good_user)
    session = client.app["presence_http"]
    assert isinstance(session, aiohttp.ClientSession)
    for token in ("a", "b", "c"):
        await post(client, token)
    assert client.app["presence_http"] is session
    assert not session.closed
    assert len(hits) == 3
    await client.close()
    assert session.closed


def test_site_me_url_default_is_unchanged():
    if "NSM_SITE_ME_URL" not in os.environ:
        assert presence.SITE_ME_URL == "https://music.nodeshift.space/api/auth/me"
