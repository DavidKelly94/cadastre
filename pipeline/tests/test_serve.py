"""The local server writes files on request, so the path guard is the part that
has to be right."""

from __future__ import annotations

import http.client
import json
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from vividhome import __version__
from vividhome.index import build_index
from vividhome.serve import MAX_BODY_BYTES, SERVICE_TYPE, make_server, service_info
from vividhome.synth import SynthSpec, build
from vividhome.upload import (
    MAX_FILE_BYTES,
    code_matches,
    display_code,
    ensure_pairing_code,
    read_pairing_code,
)


@pytest.fixture
def server(tmp_path: Path):
    store = tmp_path / "vividhome-data"
    (store / "inspect").mkdir(parents=True)
    (store / "inspect" / "main.html").write_text("<h1>plan</h1>", encoding="utf-8")

    httpd = make_server(store, port=0)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{httpd.server_address[1]}", store
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=5)


def post(base: str, payload, path: str = "/save"):
    request = urllib.request.Request(
        base + path,
        data=json.dumps(payload).encode() if not isinstance(payload, bytes) else payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return urllib.request.urlopen(request, timeout=5)


def test_serves_a_file_from_the_store(server):
    base, _ = server
    with urllib.request.urlopen(base + "/inspect/main.html", timeout=5) as response:
        assert response.status == 200
        assert b"plan" in response.read()


def test_save_writes_json_into_the_store(server):
    base, store = server
    with post(base, {"path": "plans/main.json", "data": {"level": "main"}}) as response:
        assert response.status == 200
        assert json.loads(response.read())["saved"] == "plans/main.json"

    written = json.loads((store / "plans" / "main.json").read_text(encoding="utf-8"))
    assert written == {"level": "main"}


def test_save_refuses_to_escape_the_store(server):
    base, store = server
    for escape in ["../outside.json", "../../etc/passwd.json", "plans/../../nope.json"]:
        with pytest.raises(urllib.error.HTTPError) as exc:
            post(base, {"path": escape, "data": {}})
        assert exc.value.code == 400, escape
    assert not (store.parent / "outside.json").exists()
    assert not (store.parent / "nope.json").exists()


def test_save_only_accepts_json_paths(server):
    base, _ = server
    with pytest.raises(urllib.error.HTTPError) as exc:
        post(base, {"path": "notes.txt", "data": {}})
    assert exc.value.code == 400


def test_save_rejects_a_malformed_body(server):
    base, _ = server
    with pytest.raises(urllib.error.HTTPError) as exc:
        post(base, b"{not json")
    assert exc.value.code == 400

    with pytest.raises(urllib.error.HTTPError) as exc:
        post(base, {"path": "x.json"})  # no data
    assert exc.value.code == 400


def test_only_save_accepts_a_post(server):
    base, _ = server
    with pytest.raises(urllib.error.HTTPError) as exc:
        post(base, {"path": "x.json", "data": {}}, path="/anything-else")
    assert exc.value.code == 404


def test_an_oversized_body_is_refused(server):
    base, _ = server
    request = urllib.request.Request(
        base + "/save",
        data=b"{}",
        headers={"Content-Type": "application/json", "Content-Length": str(MAX_BODY_BYTES + 1)},
        method="POST",
    )
    with pytest.raises(urllib.error.HTTPError) as exc:
        urllib.request.urlopen(request, timeout=5)
    assert exc.value.code == 413


# The LAN face of the store (ADR-0028)


@pytest.fixture
def lan_server(tmp_path: Path):
    store = tmp_path / "vividhome-data"
    (store / "inspect").mkdir(parents=True)
    (store / "inspect" / "main.html").write_text("<h1>plan</h1>", encoding="utf-8")

    httpd = make_server(store, port=0, writable=False)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{httpd.server_address[1]}", store
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=5)


def test_a_read_only_server_refuses_every_post(lan_server):
    """On the network, a writable endpoint is a way onto the owner's PC."""
    base, store = lan_server
    for path in ("/save", "/anything"):
        with pytest.raises(urllib.error.HTTPError) as exc:
            post(base, {"path": "plans/main.json", "data": {"level": "main"}}, path=path)
        assert exc.value.code == 403, path
    assert not (store / "plans").exists()


def test_a_read_only_server_still_serves_the_pages(lan_server):
    base, _ = lan_server
    with urllib.request.urlopen(base + "/inspect/main.html", timeout=5) as response:
        assert response.status == 200
        assert b"plan" in response.read()


def test_the_index_and_ping_are_served_as_json(lan_server):
    base, store = lan_server
    with urllib.request.urlopen(base + "/index.json", timeout=5) as response:
        assert response.status == 200
        assert response.headers["Content-Type"] == "application/json"
        assert response.headers["Cache-Control"] == "no-store"
        index = json.loads(response.read())
    assert index["store"] == "vividhome-data"
    assert index["projects"] == []

    with urllib.request.urlopen(base + "/_vividhome/ping?x=1", timeout=5) as response:
        assert json.loads(response.read()) == {"vividhome": __version__, "store": store.name}


def test_the_writable_server_answers_the_index_too(server):
    base, _ = server
    with urllib.request.urlopen(base + "/index.json", timeout=5) as response:
        assert "projects" in json.loads(response.read())


def test_the_bonjour_record_names_the_store_and_the_index():
    info = service_info("vividhome-data", 8765, ["192.168.1.20"])
    assert info.type == SERVICE_TYPE
    assert info.name == f"vividhome-data.{SERVICE_TYPE}"
    assert info.port == 8765
    assert info.parsed_addresses() == ["192.168.1.20"]
    assert info.properties[b"path"] == b"/index.json"
    assert info.properties[b"version"] == __version__.encode()


def test_a_store_name_with_a_dot_still_makes_a_valid_instance_name():
    info = service_info("our.house", 1, ["10.0.0.2"])
    assert info.name == f"our-house.{SERVICE_TYPE}"


def test_a_client_that_hangs_up_is_not_a_traceback(server, capsys):
    """Phones drop connections halfway through a JPEG; the CLI's output must not
    be buried under forty lines of stderr each time."""
    import socketserver

    from vividhome.serve import StoreServer

    httpd = StoreServer.__new__(StoreServer)
    socketserver.BaseServer.__init__(httpd, ("127.0.0.1", 0), None)
    try:
        raise BrokenPipeError(32, "Broken pipe")
    except BrokenPipeError:
        httpd.handle_error(None, ("127.0.0.1", 1))
    assert capsys.readouterr().err == ""

    try:
        raise ValueError("something real")
    except ValueError:
        httpd.handle_error(None, ("127.0.0.1", 1))
    assert "something real" in capsys.readouterr().err


# --- Uploads (section 14.1) -------------------------------------------------


CODE = "3f9a1c2b7e4d0a61"
SESSION = "20261103-141502_main_room_aaaaaa"
UPLOAD_SPEC = SynthSpec(keyframes=4, colour_w=160, colour_h=120)


@pytest.fixture
def paired(tmp_path: Path):
    """A server with a pairing code, the way ``serve --lan`` runs it."""
    store = tmp_path / "vividhome-data"
    store.mkdir()
    httpd = make_server(store, port=0, writable=False, pairing_code=CODE)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{httpd.server_address[1]}", store
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=5)


@pytest.fixture
def capture(tmp_path: Path) -> Path:
    return build(tmp_path / "phone" / SESSION, UPLOAD_SPEC).root


def request(base: str, method: str, path: str, body: bytes | None = None, code: str | None = CODE):
    headers = {}
    if code is not None:
        headers["Authorization"] = f"Bearer {code}"
    req = urllib.request.Request(base + path, data=body, headers=headers, method=method)
    return urllib.request.urlopen(req, timeout=10)


def status_of(call) -> tuple[int, dict]:
    try:
        with call() as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def send_session(base: str, capture: Path) -> list[str]:
    sent = []
    for item in sorted(capture.rglob("*")):
        if item.is_file():
            relative = item.relative_to(capture).as_posix()
            with request(base, "PUT", f"/upload/{SESSION}/{relative}", item.read_bytes()) as r:
                assert r.status == 201, relative
            sent.append(relative)
    return sent


def test_the_pairing_code_is_issued_once_and_read_forgivingly(tmp_path: Path):
    assert read_pairing_code(tmp_path) is None
    code = ensure_pairing_code(tmp_path)
    assert len(code) == 16 and ensure_pairing_code(tmp_path) == code
    assert read_pairing_code(tmp_path) == code
    assert display_code(code).count("-") == 3
    assert code_matches(code, display_code(code).upper())
    assert code_matches(code, " " + code + " ")
    assert not code_matches(code, code[:-1] + "0" if code[-1] != "0" else code[:-1] + "1")
    assert not code_matches(code, None)
    assert not code_matches(code, "")


def test_uploads_need_the_pairing_code(paired):
    base, _ = paired
    assert status_of(lambda: request(base, "GET", f"/upload/{SESSION}", code=None))[0] == 401
    assert status_of(lambda: request(base, "GET", f"/upload/{SESSION}", code="nope"))[0] == 401
    status, payload = status_of(
        lambda: request(base, "GET", f"/upload/{SESSION}", code="3F9A-1C2B-7E4D-0A61")
    )
    assert status == 200 and payload == {"session_id": SESSION, "state": "none", "files": {}}


def test_a_server_without_a_code_refuses_every_upload(server):
    base, _ = server
    status, payload = status_of(lambda: request(base, "GET", f"/upload/{SESSION}"))
    assert status == 403 and "serve --lan" in payload["error"]


def test_a_capture_arrives_file_by_file_and_done_ingests_it(paired, capture):
    base, store = paired
    sent = send_session(base, capture)
    assert "manifest.json" in sent and any(name.startswith("rgb/") for name in sent)

    status, listing = status_of(lambda: request(base, "GET", f"/upload/{SESSION}"))
    assert status == 200 and listing["state"] == "partial"
    assert set(listing["files"]) == set(sent)
    assert listing["files"]["manifest.json"] == (capture / "manifest.json").stat().st_size
    # The inbox is staging: the index does not know the session exists yet.
    assert build_index(store)["projects"] == []

    status, receipt = status_of(lambda: request(base, "POST", f"/upload/{SESSION}/done", b""))
    assert status == 200, receipt
    assert receipt["ingested"] and receipt["validated"], receipt
    assert receipt["errors"] == [] and receipt["plans"] == []
    destination = store / receipt["destination"]
    assert destination.is_dir() and (destination / "manifest.json").exists()
    assert (destination / "derived" / "validate.json").exists()
    assert not (store / ".inbox" / SESSION).exists()

    sessions = build_index(store)["projects"][0]["sessions"]
    assert [s["session_id"] for s in sessions] == [SESSION]
    assert sessions[0]["validated"] is True

    # Now the store has it: the listing says so and nothing may be sent again.
    status, listing = status_of(lambda: request(base, "GET", f"/upload/{SESSION}"))
    assert status == 200 and listing["state"] == "ingested"
    status, _ = status_of(lambda: request(base, "PUT", f"/upload/{SESSION}/manifest.json", b"{}"))
    assert status == 409
    status, _ = status_of(lambda: request(base, "POST", f"/upload/{SESSION}/done", b""))
    assert status == 409


def test_plans_beside_the_session_come_across(paired, capture):
    base, store = paired
    send_session(base, capture)
    png = b"\x89PNG\r\n\x1a\n" + b"\0" * 32
    plan = {
        "level": "main",
        "image": "main.png",
        "metres_per_pixel": None,
        "origin_px": None,
        "rotation_deg": 0.0,
        "floor_height_m": 0.0,
    }
    with request(base, "PUT", f"/upload/{SESSION}/plans/main.png", png) as r:
        assert r.status == 201
    with request(base, "PUT", f"/upload/{SESSION}/plans/main.json", json.dumps(plan).encode()) as r:
        assert r.status == 201
    status, listing = status_of(lambda: request(base, "GET", f"/upload/{SESSION}"))
    assert listing["files"]["plans/main.png"] == len(png)

    status, receipt = status_of(lambda: request(base, "POST", f"/upload/{SESSION}/done", b""))
    assert status == 200 and receipt["validated"]
    assert [(p["level"], p["imported"]) for p in receipt["plans"]] == [("main", True)]
    assert (store / "plans" / "main.png").read_bytes() == png
    assert json.loads((store / "plans" / "main.json").read_text())["level"] == "main"


def test_a_capture_that_fails_validation_is_kept_and_said_so(paired, capture):
    base, store = paired
    # Only the manifest: every referenced file is missing, which validate reports.
    with request(
        base, "PUT", f"/upload/{SESSION}/manifest.json", (capture / "manifest.json").read_bytes()
    ) as r:
        assert r.status == 201
    status, receipt = status_of(lambda: request(base, "POST", f"/upload/{SESSION}/done", b""))
    assert status == 200, receipt
    assert receipt["ingested"] and receipt["validated"] is False
    assert receipt["errors"], "the first errors travel back so the phone can show them"
    assert (store / receipt["destination"] / "manifest.json").exists()
    sessions = build_index(store)["projects"][0]["sessions"]
    assert sessions[0]["validated"] is False


def test_done_with_nothing_to_ingest_says_so(paired):
    base, _ = paired
    with request(base, "PUT", f"/upload/{SESSION}/rgb/000000.jpg", b"\xff\xd8") as r:
        assert r.status == 201
    status, payload = status_of(lambda: request(base, "POST", f"/upload/{SESSION}/done", b""))
    assert status == 400 and "manifest.json" in payload["error"]


def test_upload_paths_are_checked_as_text_and_as_paths(paired):
    base, store = paired
    refused = [
        "../outside.jpg",
        "rgb/../../outside.jpg",
        "a/b/c.jpg",
        ".hidden",
        "rgb/.hidden",
        "derived/validate.json",
        "plans",
        "rgb/",
        "rgb//000001.jpg",
        "rgb/0001;rm.jpg",
    ]
    for path in refused:
        status, payload = status_of(
            lambda path=path: request(base, "PUT", f"/upload/{SESSION}/{path}", b"x")
        )
        assert status == 400, (path, payload)
    assert not (store / "outside.jpg").exists() and not (store.parent / "outside.jpg").exists()
    inbox = store / ".inbox" / SESSION
    assert not inbox.exists() or not any(inbox.rglob("*.jpg"))

    for bad_id in [
        "kitchen",
        "20261103-141502_main_room_AAAAAA",
        "../x",
        "20261103-141502_main_room_aaaaaa1",
    ]:
        status, _ = status_of(
            lambda bad_id=bad_id: request(base, "PUT", f"/upload/{bad_id}/manifest.json", b"{}")
        )
        assert status == 400, bad_id


def test_a_file_too_large_is_refused_before_it_is_read(paired):
    base, store = paired
    host, port = base.removeprefix("http://").split(":")
    conn = http.client.HTTPConnection(host, int(port), timeout=10)
    conn.putrequest("PUT", f"/upload/{SESSION}/mesh.obj")
    conn.putheader("Authorization", f"Bearer {CODE}")
    conn.putheader("Content-Length", str(MAX_FILE_BYTES + 1))
    conn.endheaders()
    response = conn.getresponse()
    assert response.status == 413
    conn.close()
    assert not (store / ".inbox" / SESSION / SESSION / "mesh.obj").exists()


def test_a_body_that_ends_early_leaves_nothing_under_the_final_name(paired):
    base, store = paired
    host, port = base.removeprefix("http://").split(":")
    conn = http.client.HTTPConnection(host, int(port), timeout=10)
    conn.putrequest("PUT", f"/upload/{SESSION}/rgb/000001.jpg")
    conn.putheader("Authorization", f"Bearer {CODE}")
    conn.putheader("Content-Length", "100")
    conn.endheaders()
    conn.send(b"0123456789")
    conn.close()

    # The server noticed the short body on its own time; wait for it to settle.
    target = store / ".inbox" / SESSION / SESSION / "rgb"
    for _ in range(50):
        if not any(target.glob("*.part")) if target.exists() else True:
            break
        time.sleep(0.05)
    assert not (target / "000001.jpg").exists()
    assert not target.exists() or not any(target.glob("*.part"))
    _, listing = status_of(lambda: request(base, "GET", f"/upload/{SESSION}"))
    assert listing["files"] == {}


def test_a_resent_file_replaces_the_earlier_one(paired):
    base, store = paired
    with request(base, "PUT", f"/upload/{SESSION}/log.txt", b"first") as r:
        assert r.status == 201
    with request(base, "PUT", f"/upload/{SESSION}/log.txt", b"second, longer") as r:
        assert json.loads(r.read())["bytes"] == len(b"second, longer")
    assert (store / ".inbox" / SESSION / SESSION / "log.txt").read_bytes() == b"second, longer"


def test_a_read_only_lan_server_still_refuses_save(paired):
    base, _ = paired
    with pytest.raises(urllib.error.HTTPError) as exc:
        post(base, {"path": "plans/main.json", "data": {}})
    assert exc.value.code == 403
