"""The browser handshake, and what can be checked about pages without a browser."""

from __future__ import annotations

import json
import re
import threading
import urllib.request
from pathlib import Path

import pytest

from vividhome.webflow import WEB_DIRNAME, collect, stage, web_dir

PAGES = ["calibrate.html", "align.html"]


def page_source(name: str) -> str:
    return (Path(__file__).parents[1] / "vividhome" / "web" / name).read_text(encoding="utf-8")


# What can be checked about a hand-written page without running it


@pytest.mark.parametrize("name", PAGES)
def test_the_page_ships_with_the_package(name: str):
    assert (Path(__file__).parents[1] / "vividhome" / "web" / name).exists()


@pytest.mark.parametrize("name", PAGES)
def test_every_element_the_script_looks_up_actually_exists(name: str):
    """A typo in getElementById is silent in a browser and fatal to the page."""
    source = page_source(name)
    declared = set(re.findall(r'id="([^"]+)"', source))
    looked_up = set(re.findall(r'getElementById\("([^"]+)"\)', source))
    looked_up |= set(re.findall(r'\bel\("([^"]+)"\)', source))
    missing = looked_up - declared
    assert not missing, f"{name} looks up ids that do not exist: {sorted(missing)}"


@pytest.mark.parametrize("name", PAGES)
def test_the_page_loads_nothing_external(name: str):
    source = page_source(name)
    assert "<script src" not in source
    assert "<link" not in source
    assert "https://" not in source
    assert "http://" not in source.replace("http://www.w3.org/2000/svg", "")


@pytest.mark.parametrize("name", PAGES)
def test_the_page_posts_to_the_path_the_task_gives_it(name: str):
    """The page must not choose where it writes; the command decides."""
    source = page_source(name)
    assert "task.result_path" in source
    assert '"/save"' in source


# The handshake


def test_stage_writes_the_task_and_the_page(tmp_path: Path):
    task = stage(tmp_path, "calibrate.html", {"level": "main", "image": "../plans/main.png"})

    assert task.directory == web_dir(tmp_path)
    assert (task.directory / "calibrate.html").exists()

    payload = json.loads(task.task_path.read_text(encoding="utf-8"))
    assert payload["level"] == "main"
    assert payload["result_path"] == f"{WEB_DIRNAME}/result.json"


def test_stage_clears_anything_left_from_last_time(tmp_path: Path):
    stale = web_dir(tmp_path)
    stale.mkdir(parents=True)
    (stale / "result.json").write_text('{"kind": "stale"}', encoding="utf-8")

    task = stage(tmp_path, "calibrate.html", {"level": "main"})
    assert not task.result_path.exists(), "a stale result would be read as a fresh click"


def test_collect_returns_what_the_page_posted(tmp_path: Path):
    task = stage(tmp_path, "calibrate.html", {"level": "main"})
    posted = {"kind": "calibrate", "level": "main", "distance": "3.81m"}

    def post_when_ready():
        # Wait for the server, then post the way the page does.
        for _ in range(200):
            try:
                request = urllib.request.Request(
                    "http://127.0.0.1:8791/save",
                    data=json.dumps({"path": task.relative_result, "data": posted}).encode(),
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                urllib.request.urlopen(request, timeout=2)
                return
            except Exception:  # noqa: BLE001 - the server may not be up yet
                threading.Event().wait(0.05)

    thread = threading.Thread(target=post_when_ready, daemon=True)
    thread.start()

    result = collect(tmp_path, task, port=8791, timeout_s=20, open_browser=False)
    thread.join(timeout=5)

    assert result == posted


def test_collect_cleans_up_even_when_nothing_is_posted(tmp_path: Path):
    task = stage(tmp_path, "calibrate.html", {"level": "main"})
    result = collect(tmp_path, task, port=8792, timeout_s=0.4, open_browser=False, poll_s=0.05)

    assert result is None
    assert not task.directory.exists(), "staging must not survive a give-up"


def test_collect_removes_the_staging_directory_after_success(tmp_path: Path):
    task = stage(tmp_path, "calibrate.html", {"level": "main"})
    task.result_path.write_text(json.dumps({"kind": "calibrate"}), encoding="utf-8")

    result = collect(tmp_path, task, port=8793, timeout_s=5, open_browser=False, poll_s=0.05)
    assert result == {"kind": "calibrate"}
    assert not task.directory.exists()


def test_the_served_page_is_reachable(tmp_path: Path):
    """The URL the command prints has to actually serve the page."""
    task = stage(tmp_path, "align.html", {"level": "main"})

    fetched: dict = {}

    def fetch():
        for _ in range(200):
            try:
                url = f"http://127.0.0.1:8794/{WEB_DIRNAME}/align.html"
                with urllib.request.urlopen(url, timeout=2) as response:
                    fetched["body"] = response.read().decode()
                # Then post so collect returns promptly.
                request = urllib.request.Request(
                    "http://127.0.0.1:8794/save",
                    data=json.dumps({"path": task.relative_result, "data": {"ok": True}}).encode(),
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                urllib.request.urlopen(request, timeout=2)
                return
            except Exception:  # noqa: BLE001
                threading.Event().wait(0.05)

    thread = threading.Thread(target=fetch, daemon=True)
    thread.start()
    collect(tmp_path, task, port=8794, timeout_s=20, open_browser=False)
    thread.join(timeout=5)

    assert "VividHome — align session" in fetched.get("body", "")
