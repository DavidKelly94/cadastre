"""A tiny local server for the generated pages.

Only what the pages need: serve the store's files, and accept a POST of JSON to
save. It binds to localhost by default because it writes files on request and
there is no authentication — this is a tool the owner runs on their own PC, not
a service.
"""

from __future__ import annotations

import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

__all__ = ["make_server", "serve"]

#: The most a single POST may carry. Generous for a list of clicked points, small
#: enough that a runaway request cannot fill memory.
MAX_BODY_BYTES = 4 * 1024 * 1024


class StoreHandler(SimpleHTTPRequestHandler):
    """Serves the store read-only, plus ``POST /save`` for the calibration pages."""

    def __init__(self, *args, root: Path, **kwargs):
        self._root = root
        super().__init__(*args, directory=str(root), **kwargs)

    def log_message(self, format: str, *args) -> None:
        # The default logs every request to stderr, which buries the CLI's output.
        pass

    def do_POST(self) -> None:
        if self.path != "/save":
            self.send_error(404, "only /save accepts a POST")
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400, "bad Content-Length")
            return
        if length <= 0 or length > MAX_BODY_BYTES:
            self.send_error(413, "body missing or too large")
            return

        try:
            payload = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_error(400, "body is not JSON")
            return
        if not isinstance(payload, dict) or "path" not in payload or "data" not in payload:
            self.send_error(400, "expected {path, data}")
            return

        try:
            target = self._resolve(str(payload["path"]))
        except ValueError as error:
            self.send_error(400, str(error))
            return

        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(payload["data"], indent=2), encoding="utf-8")

        body = json.dumps({"saved": str(target.relative_to(self._root))}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _resolve(self, relative: str) -> Path:
        """Resolve a requested save path, refusing anything outside the store.

        The page supplies this path, so it is untrusted input even though the
        page is local: a stray '..' must not let a save land anywhere on disk.
        """
        if not relative.endswith(".json"):
            raise ValueError("only .json paths may be saved")
        target = (self._root / relative).resolve()
        if not target.is_relative_to(self._root.resolve()):
            raise ValueError("path escapes the store")
        return target


def make_server(store: str | Path, *, host: str = "127.0.0.1", port: int = 0):
    """Build a server rooted at the store. Port 0 asks the OS for a free one."""
    root = Path(store).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return ThreadingHTTPServer((host, port), partial(StoreHandler, root=root))


def serve(
    store: str | Path, *, host: str = "127.0.0.1", port: int = 8765, open_path: str = ""
) -> None:
    """Serve the store until interrupted."""
    server = make_server(store, host=host, port=port)
    actual = server.server_address[1]
    print(f"serving {Path(store).resolve()} at http://{host}:{actual}/{open_path}")
    print("press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        server.server_close()
