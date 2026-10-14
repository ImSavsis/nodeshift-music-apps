import asyncio
import time

import pytest

import nsm_bump


@pytest.fixture
def fast_wait(monkeypatch):
    monkeypatch.setattr(nsm_bump, "BUMP_WAIT_SECONDS", 0.6)


async def make_client(aiohttp_client):
    return await aiohttp_client(nsm_bump.make_app())


def payload(device, impact, can_host=True, name="phone"):
    return {"device": device, "impact_ms": impact, "offset_ms": 0, "name": name, "platform": "ios", "can_host": can_host}


async def test_time(aiohttp_client):
    client = await make_client(aiohttp_client)
    response = await client.get("/time")
    body = await response.json()
    assert response.status == 200
    assert abs(body["now"] - int(time.time() * 1000)) < 5000


async def test_matching_bumps_get_roles(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    base = int(time.time() * 1000)
    first, second = await asyncio.gather(
        client.post("/bump", json=payload("device-a", base)),
        client.post("/bump", json=payload("device-b", base + 120)),
    )
    one, two = await first.json(), await second.json()
    assert one["matched"] and two["matched"]
    assert one["pair"] == two["pair"]
    assert {one["role"], two["role"]} == {"host", "guest"}
    assert one["role"] == "host"


async def test_far_apart_bumps_do_not_match(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    base = int(time.time() * 1000)
    first, second = await asyncio.gather(
        client.post("/bump", json=payload("device-a", base)),
        client.post("/bump", json=payload("device-b", base + 2000)),
    )
    assert (await first.json())["matched"] is False
    assert (await second.json())["matched"] is False


async def test_same_device_never_matches_itself(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    base = int(time.time() * 1000)
    first, second = await asyncio.gather(
        client.post("/bump", json=payload("device-a", base)),
        client.post("/bump", json=payload("device-a", base + 50)),
    )
    results = [await first.json(), await second.json()]
    assert all(item["matched"] is False for item in results)


async def test_only_logged_in_phone_hosts(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    base = int(time.time() * 1000)
    first, second = await asyncio.gather(
        client.post("/bump", json=payload("device-a", base, can_host=False)),
        client.post("/bump", json=payload("device-z", base + 40, can_host=True)),
    )
    roles = {"device-a": (await first.json())["role"], "device-z": (await second.json())["role"]}
    assert roles == {"device-a": "guest", "device-z": "host"}


async def test_nobody_can_host(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    base = int(time.time() * 1000)
    first, second = await asyncio.gather(
        client.post("/bump", json=payload("device-a", base, can_host=False)),
        client.post("/bump", json=payload("device-b", base + 40, can_host=False)),
    )
    assert (await first.json())["error"] == "login_required"
    assert (await second.json())["error"] == "login_required"


async def pair_up(client):
    base = int(time.time() * 1000)
    first, second = await asyncio.gather(
        client.post("/bump", json=payload("device-a", base)),
        client.post("/bump", json=payload("device-b", base + 80)),
    )
    return (await first.json())["pair"]


async def test_host_publishes_code_guest_receives(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    pair = await pair_up(client)
    waiting = asyncio.ensure_future(client.get(f"/pair/{pair}/room", params={"device": "device-b", "wait": "5"}))
    await asyncio.sleep(0.1)
    published = await client.post(f"/pair/{pair}/room", json={"device": "device-a", "code": "ab12cd"})
    assert published.status == 200
    response = await waiting
    assert response.status == 200
    assert (await response.json())["code"] == "AB12CD"


async def test_only_host_may_publish(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    pair = await pair_up(client)
    response = await client.post(f"/pair/{pair}/room", json={"device": "device-b", "code": "ABCDEF"})
    assert response.status == 403


async def test_bad_code_is_rejected(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    pair = await pair_up(client)
    response = await client.post(f"/pair/{pair}/room", json={"device": "device-a", "code": "no way!"})
    assert response.status == 400


async def test_fetch_without_code_times_out_with_204(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    pair = await pair_up(client)
    response = await client.get(f"/pair/{pair}/room", params={"device": "device-b", "wait": "0.2"})
    assert response.status == 204


async def test_stranger_cannot_fetch(aiohttp_client, fast_wait):
    client = await make_client(aiohttp_client)
    pair = await pair_up(client)
    response = await client.get(f"/pair/{pair}/room", params={"device": "intruder"})
    assert response.status == 403


async def test_unknown_pair(aiohttp_client):
    client = await make_client(aiohttp_client)
    response = await client.get("/pair/nothing/room", params={"device": "device-a"})
    assert response.status == 404


async def test_rate_limit(aiohttp_client, monkeypatch):
    monkeypatch.setattr(nsm_bump, "BUMP_WAIT_SECONDS", 0.01)
    monkeypatch.setattr(nsm_bump, "RATE_LIMIT", 3)
    client = await make_client(aiohttp_client)
    statuses = []
    for index in range(5):
        response = await client.post("/bump", json=payload(f"device-{index}", int(time.time() * 1000)))
        statuses.append(response.status)
    assert statuses[:3] == [200, 200, 200]
    assert statuses[3:] == [429, 429]
