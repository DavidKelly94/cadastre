"""The local server writes files on request, so the path guard is the part that
has to be right."""

from __future__ import annotations

import json
import threading
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from vividhome import __version__
from vividhome.serve import MAX_BODY_BYTES, SERVICE_TYPE, make_server, service_info


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
