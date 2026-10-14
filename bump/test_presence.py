import asyncio
import time

import pytest
from aiohttp import web

import nsm_bump
import presence


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


async def test_requires_token(aiohttp_client):
    client = await make_client(aiohttp_client)
    assert (await client.post("/presence", json=state())).status == 401
    assert (await client.post("/presence", json=state(), headers=auth("nope"))).status == 401
    assert (await client.get("/presence/ws")).status == 401


async def test_update_reaches_sink_of_same_user_only(aiohttp_client):
    client = await make_client(aiohttp_client)
    mine = await client.ws_connect("/presence/ws", headers=auth("good-a"))
    other = await client.ws_connect("/presence/ws", headers=auth("good-b"))
    assert (await mine.receive_json())["type"] == "clear"
    assert (await other.receive_json())["type"] == "clear"
    response = await client.post("/presence", json=state(), headers=auth("good-a"))
    assert response.status == 200
    message = await mine.receive_json(timeout=3)
    assert message["type"] == "presence"
    assert message["title"] == "Everyday"
    assert message["site_id"] == "183"
    assert message["ts"] > 0
    with pytest.raises(asyncio.TimeoutError):
        await other.receive_json(timeout=0.4)


async def test_new_sink_gets_current_state(aiohttp_client):
    client = await make_client(aiohttp_client)
    await client.post("/presence", json=state(), headers=auth("good-a"))
    sink = await client.ws_connect("/presence/ws?token=good-a")
    message = await sink.receive_json()
    assert message["type"] == "presence"
    assert message["artist"] == "Jamiroquai"


async def test_stop_clears(aiohttp_client):
    client = await make_client(aiohttp_client)
    sink = await client.ws_connect("/presence/ws", headers=auth("good-a"))
    await sink.receive_json()
    await client.post("/presence", json=state(), headers=auth("good-a"))
    await sink.receive_json()
    await client.post("/presence", json={"stop": True}, headers=auth("good-a"))
    assert (await sink.receive_json())["type"] == "clear"


async def test_cleaning(aiohttp_client):
    client = await make_client(aiohttp_client)
    sink = await client.ws_connect("/presence/ws", headers=auth("good-a"))
    await sink.receive_json()
    await client.post("/presence", json=state(cover="http://insecure/x.jpg", site_id="abc", title="x" * 500), headers=auth("good-a"))
    message = await sink.receive_json()
    assert message["cover"] == ""
    assert message["site_id"] == ""
    assert len(message["title"]) == 128
    assert (await client.post("/presence", json={"title": ""}, headers=auth("good-a"))).status == 400


async def test_art_upload_and_fetch(aiohttp_client, tmp_path, monkeypatch):
    monkeypatch.setattr(presence, "ART_DIR", tmp_path)
    client = await make_client(aiohttp_client)
    data = b"\xff\xd8\xff" + b"0" * 100
    response = await client.post("/presence/art", data=data, headers={**auth("good-a"), "Content-Type": "image/jpeg"})
    assert response.status == 200
    url = (await response.json())["url"]
    name = url.rsplit("/", 1)[1]
    fetched = await client.get(f"/art/{name}")
    assert fetched.status == 200
    assert await fetched.read() == data
    assert (await client.get("/art/../etc.jpg")).status == 404


async def test_art_rejects_wrong_type_and_size(aiohttp_client, tmp_path, monkeypatch):
    monkeypatch.setattr(presence, "ART_DIR", tmp_path)
    client = await make_client(aiohttp_client)
    bad = await client.post("/presence/art", data=b"x", headers={**auth("good-a"), "Content-Type": "text/plain"})
    assert bad.status == 415
    big = await client.post("/presence/art", data=b"0" * 700_000, headers={**auth("good-a"), "Content-Type": "image/jpeg"})
    assert big.status == 413


async def test_stale_state_swept(aiohttp_client):
    client = await make_client(aiohttp_client)
    hub = client.app["presence"]
    await client.post("/presence", json=state(), headers=auth("good-a"))
    hub.states["1"]["ts"] = int(time.time() * 1000) - 120_000
    assert hub.sweep_stale() == ["1"]
    assert "1" not in hub.states


async def test_poll_returns_immediately_when_version_differs(aiohttp_client):
    client = await make_client(aiohttp_client)
    await client.post("/presence", json=state(), headers=auth("good-a"))
    response = await client.get("/presence/poll", params={"since": "0", "wait": "5"}, headers=auth("good-a"))
    body = await response.json()
    assert body["version"] >= 1
    assert body["state"]["title"] == "Everyday"


async def test_poll_waits_for_change(aiohttp_client):
    client = await make_client(aiohttp_client)
    first = await (await client.get("/presence/poll", params={"since": "-1"}, headers=auth("good-a"))).json()
    waiting = asyncio.ensure_future(client.get("/presence/poll", params={"since": str(first["version"]), "wait": "5"}, headers=auth("good-a")))
    await asyncio.sleep(0.2)
    await client.post("/presence", json=state(title="Later"), headers=auth("good-a"))
    body = await (await waiting).json()
    assert body["state"]["title"] == "Later"


async def test_poll_times_out_with_same_version(aiohttp_client):
    client = await make_client(aiohttp_client)
    first = await (await client.get("/presence/poll", params={"since": "-1"}, headers=auth("good-a"))).json()
    body = await (await client.get("/presence/poll", params={"since": str(first["version"]), "wait": "0.3"}, headers=auth("good-a"))).json()
    assert body["version"] == first["version"]
    assert body["state"] is None
