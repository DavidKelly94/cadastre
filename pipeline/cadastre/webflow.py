"""The handshake between a command and its browser page.

Both interactive steps work the same way, and neither puts any arithmetic in the
page:

1. the command stages a task file describing what is being calibrated or aligned;
2. it serves the store and prints a URL;
3. the page reads the task, collects clicks, and POSTs a result;
4. the command reads the result, applies it through the ordinary code path, and
   deletes the staging directory.

The page is only ever a way of collecting points. Everything that could be wrong
about the geometry is on this side, where it is tested.
"""

from __future__ import annotations

import json
import shutil
import threading
import time
import webbrowser
from dataclasses import dataclass
from pathlib import Path

from .serve import make_server

__all__ = ["WebTask", "collect", "stage", "web_dir"]

#: Where task and result files live while a page is open. Inside the store so the
#: server can reach them, dot-prefixed so it is obviously not part of the record.
WEB_DIRNAME = ".web"


def web_dir(store: str | Path) -> Path:
    return Path(store) / WEB_DIRNAME


@dataclass
class WebTask:
    """A staged interaction: the page to open and the files it exchanges."""

    page: str
    directory: Path
    task_path: Path
    result_path: Path
    relative_result: str


def stage(store: str | Path, page: str, task: dict) -> WebTask:
    """Write the task file and the page into ``<store>/.web/``."""
    directory = web_dir(store)
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)

    source = Path(__file__).parent / "web" / page
    if not source.exists():  # pragma: no cover - packaging error, not a user path
        raise FileNotFoundError(f"missing page template: {source}")
    shutil.copyfile(source, directory / page)

    relative_result = f"{WEB_DIRNAME}/result.json"
    payload = {**task, "result_path": relative_result}
    (directory / "task.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")

    return WebTask(
        page=page,
        directory=directory,
        task_path=directory / "task.json",
        result_path=directory / "result.json",
        relative_result=relative_result,
    )


def collect(
    store: str | Path,
    task: WebTask,
    *,
    port: int = 8765,
    timeout_s: float = 900.0,
    open_browser: bool = True,
    poll_s: float = 0.25,
) -> dict | None:
    """Serve the store until the page posts a result, or the wait runs out.

    Returns the posted result, or None if the owner gave up. The staging
    directory is removed either way: a stale result file left behind would be
    picked up by the next run as though it had just been clicked.
    """
    server = make_server(store, port=port)
    address = f"http://127.0.0.1:{server.server_address[1]}/{WEB_DIRNAME}/{task.page}"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    print(f"open {address}")
    print("waiting for the page to save; press Ctrl+C to give up")
    if open_browser:
        with _suppressed():
            webbrowser.open(address)

    deadline = time.monotonic() + timeout_s
    result: dict | None = None
    try:
        while time.monotonic() < deadline:
            if task.result_path.exists():
                # The file may still be mid-write when it first appears.
                try:
                    result = json.loads(task.result_path.read_text(encoding="utf-8"))
                    break
                except json.JSONDecodeError:
                    pass
            time.sleep(poll_s)
        else:
            print("timed out waiting for the page")
    except KeyboardInterrupt:
        print("\ngave up waiting")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        shutil.rmtree(task.directory, ignore_errors=True)

    return result


class _suppressed:
    """webbrowser.open raises on a headless machine; that is not a failure."""

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return exc_type is not None and issubclass(exc_type, Exception)
