"""The local server writes files on request, so the path guard is the part that
has to be right."""

from __future__ import annotations

import json
import threading
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from cadastre.serve import MAX_BODY_BYTES, make_server


@pytest.fixture
def server(tmp_path: Path):
    store = tmp_path / "cadastre-data"
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
