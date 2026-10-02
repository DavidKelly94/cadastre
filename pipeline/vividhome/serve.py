"""A tiny local server for the generated pages, and the LAN face of the store.

Two modes, and the difference between them is what may be written.

On localhost, as before: serve the store's files and accept a ``POST /save`` of
JSON, which the calibrate and align pages use. It binds to ``127.0.0.1`` because
it writes files on request and there is no authentication.

With ``--lan`` (ADR-0028): serve the same files on every interface so the phone
can read the rendering, answer ``GET /index.json`` with what the store holds
(section 14), advertise over Bonjour so the app finds the PC without an address
being typed, and refuse ``/save``. A writable endpoint on the home network would
be a way to put files on the owner's PC from any device on it.

The one thing that may be written from the network is a capture, under
``/upload/`` (section 14.1, ADR-0029), and only with the store's pairing code,
which ``--lan`` issues and prints. Uploads land in an inbox, never the store;
``ingest`` takes them from there. Behind ``tailscale serve`` this is reachable
from wherever the owner is, which is the point; it is still a tool the owner
runs on their own PC for their own phone, not a service.
"""

from __future__ import annotations

import json
import socket
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import __version__
from .index import build_index
from .upload import (
    PAIRING_FILE,
    Inbox,
    UploadError,
    code_matches,
    display_code,
    ensure_pairing_code,
    read_pairing_code,
)

__all__ = ["SERVICE_TYPE", "Advertisement", "StoreServer", "make_server", "serve", "service_info"]

#: The most a single POST may carry. Generous for a list of clicked points, small
#: enough that a runaway request cannot fill memory.
MAX_BODY_BYTES = 4 * 1024 * 1024

#: The Bonjour service type the app looks for. Matches ``NSBonjourServices`` in
#: ``ios/project.yml`` once the app side lands; change both or neither.
SERVICE_TYPE = "_vividhome._tcp.local."


class StoreHandler(SimpleHTTPRequestHandler):
    """Serves the store read-only, plus ``POST /save`` when writable and
    ``/upload/`` when the store has a pairing code."""

    # Keep-alive: a capture is thousands of small PUTs, and a connection per
    # request would spend most of the send on handshakes. Every response below
    # carries a Content-Length, which HTTP/1.1 needs, and a refusal that leaves
    # a body unread closes the connection rather than parse the body as the
    # next request.
    protocol_version = "HTTP/1.1"

    def __init__(
        self,
        *args,
        root: Path,
        writable: bool = True,
        pairing_code: str | None = None,
        **kwargs,
    ):
        self._root = root
        self._writable = writable
        self._pairing_code = pairing_code
        self._inbox = Inbox(root) if pairing_code else None
        super().__init__(*args, directory=str(root), **kwargs)

    def log_message(self, format: str, *args) -> None:
        # The default logs every request to stderr, which buries the CLI's output.
        pass

    def send_error(self, code, message=None, explain=None) -> None:
        self.close_connection = True
        super().send_error(code, message, explain)

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/index.json":
            self._send_json(build_index(self._root))
            return
        if path == "/_vividhome/ping":
            self._send_json({"vividhome": __version__, "store": self._root.name})
            return
        if path.startswith("/upload/"):
            self._upload("GET", path)
            return
        super().do_GET()

    def do_PUT(self) -> None:
        path = self.path.split("?", 1)[0]
        if path.startswith("/upload/"):
            self._upload("PUT", path)
            return
        self.send_error(404, "only /upload/ accepts a PUT")

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        if path.startswith("/upload/"):
            self._upload("POST", path)
            return
        if not self._writable:
            self.send_error(403, "this server is read-only on the network")
            return
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
        self._send_json({"saved": str(target.relative_to(self._root))})

    # --- Uploads (section 14.1) ---------------------------------------------

    def _upload(self, method: str, path: str) -> None:
        """Route one request under ``/upload/``; every refusal is JSON with a status."""
        try:
            if self._inbox is None or not self._pairing_code:
                raise UploadError(
                    403,
                    "uploads are not enabled here; run 'vividhome serve --lan' once "
                    "to issue a pairing code",
                )
            self._authorise()
            session_id, _, rest = path[len("/upload/") :].partition("/")
            if method == "GET" and not rest:
                self._send_json(self._inbox.listing(session_id))
            elif method == "PUT" and rest:
                try:
                    length = int(self.headers.get("Content-Length", ""))
                except ValueError:
                    raise UploadError(411, "a PUT needs a Content-Length") from None
                stored = self._inbox.store_file(session_id, rest, self.rfile, length)
                self._send_json({"stored": rest, "bytes": stored}, status=201)
            elif method == "POST" and rest == "done":
                self._send_json(self._inbox.finish(session_id))
            else:
                raise UploadError(
                    404,
                    "under /upload/: GET <session-id>, PUT <session-id>/<path>, "
                    "POST <session-id>/done",
                )
        except UploadError as error:
            # The body, if any, is unread; the connection goes with the answer.
            self.close_connection = True
            self._send_json({"error": error.message}, status=error.status)

    def _authorise(self) -> None:
        header = self.headers.get("Authorization", "")
        scheme, _, presented = header.partition(" ")
        if scheme.lower() != "bearer" or not code_matches(self._pairing_code or "", presented):
            raise UploadError(401, "the pairing code is missing or wrong")

    def _send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
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


class StoreServer(ThreadingHTTPServer):
    """A threading server that does not print a traceback when a client hangs up.

    A phone that closes a connection halfway through a JPEG is normal on a
    LAN, and the default handler answers it with forty lines on stderr, which
    is the one thing the CLI's output must not be buried under. Anything that
    is not a dropped connection is still reported as before.
    """

    def handle_error(self, request, client_address) -> None:
        error = sys.exc_info()[1]
        if isinstance(error, BrokenPipeError | ConnectionResetError | ConnectionAbortedError):
            return
        super().handle_error(request, client_address)


def make_server(
    store: str | Path,
    *,
    host: str = "127.0.0.1",
    port: int = 0,
    writable: bool = True,
    pairing_code: str | None = None,
):
    """Build a server rooted at the store. Port 0 asks the OS for a free one.
    Uploads are accepted only when a ``pairing_code`` is given."""
    root = Path(store).resolve()
    root.mkdir(parents=True, exist_ok=True)
    handler = partial(StoreHandler, root=root, writable=writable, pairing_code=pairing_code)
    return StoreServer((host, port), handler)


def lan_addresses() -> list[str]:
    """The IPv4 addresses this machine has on its networks, loopback excluded."""
    found: set[str] = set()
    try:
        import ifaddr

        for adapter in ifaddr.get_adapters():
            for ip in adapter.ips:
                if ip.is_IPv4 and not str(ip.ip).startswith("127."):
                    found.add(str(ip.ip))
    except ImportError:  # pragma: no cover - ifaddr comes with zeroconf
        pass
    if not found:
        try:
            for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
                if not info[4][0].startswith("127."):
                    found.add(info[4][0])
        except socket.gaierror:
            pass
    return sorted(found)


def service_info(name: str, port: int, addresses: list[str]):
    """The Bonjour record for one store: ``<name>._vividhome._tcp.local.``."""
    from zeroconf import ServiceInfo

    # An instance name may not contain a dot; the store's folder name might.
    instance = name.replace(".", "-") or "vividhome"
    return ServiceInfo(
        SERVICE_TYPE,
        f"{instance}.{SERVICE_TYPE}",
        addresses=[socket.inet_aton(address) for address in addresses],
        port=port,
        properties={"store": name, "version": __version__, "path": "/index.json"},
        server=f"{socket.gethostname().split('.')[0]}.local.",
    )


class Advertisement:
    """Register the store on the local network for as long as this lives."""

    def __init__(self, name: str, port: int, addresses: list[str]):
        from zeroconf import Zeroconf

        self._zeroconf = Zeroconf()
        self._info = service_info(name, port, addresses)
        self._zeroconf.register_service(self._info)

    def close(self) -> None:
        try:
            self._zeroconf.unregister_service(self._info)
        finally:
            self._zeroconf.close()


def serve(
    store: str | Path,
    *,
    host: str = "127.0.0.1",
    port: int = 8765,
    open_path: str = "",
    lan: bool = False,
) -> None:
    """Serve the store until interrupted. ``lan`` listens everywhere, read-only."""
    root = Path(store).resolve()
    if lan:
        host = "0.0.0.0"
    # --lan issues the pairing code; plain serve honours one that exists, so
    # the same store answers uploads either way once it has been paired.
    code = ensure_pairing_code(root) if lan else read_pairing_code(root)
    server = make_server(root, host=host, port=port, writable=not lan, pairing_code=code)
    actual = server.server_address[1]

    advertisement: Advertisement | None = None
    if lan:
        addresses = lan_addresses()
        print(f"serving {root} on the network")
        for address in addresses or ["<no network address found>"]:
            print(f"  http://{address}:{actual}/{open_path}")
        print("  anyone on this network can read the store; only the app, with the pairing")
        print("  code, can send captures in, and those land in an inbox for ingest")
        print(f"  pairing code {display_code(code or '')}: type it in the app under PC")
        print(f"  (kept in {root / PAIRING_FILE}; delete that file to issue a new one)")
        try:
            advertisement = Advertisement(root.name, actual, addresses)
            print(f"  advertised as {root.name} ({SERVICE_TYPE[:-1]}) for the app to find")
        except OSError as error:
            print(f"  not advertised over Bonjour ({error}); type the address in the app")
    else:
        print(f"serving {root} at http://{host}:{actual}/{open_path}")
    print("press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        if advertisement is not None:
            advertisement.close()
        server.server_close()
