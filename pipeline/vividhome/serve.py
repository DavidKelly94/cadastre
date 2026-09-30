"""A tiny local server for the generated pages, and the LAN face of the store.

Two modes, and the difference between them is what may be written.

On localhost, as before: serve the store's files and accept a ``POST /save`` of
JSON, which the calibrate and align pages use. It binds to ``127.0.0.1`` because
it writes files on request and there is no authentication.

With ``--lan`` (ADR-0028): serve the same files on every interface so the phone
can read the rendering, answer ``GET /index.json`` with what the store holds
(section 14), advertise over Bonjour so the app finds the PC without an address
being typed, and **refuse every POST**. A writable endpoint on the home network
would be a way to put files on the owner's PC from any device on it. This is a
tool the owner runs on their own PC for their own phone, not a service; nothing
here should be reachable from outside the house.
"""

from __future__ import annotations

import json
import socket
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import __version__
from .index import build_index

__all__ = ["SERVICE_TYPE", "Advertisement", "make_server", "serve", "service_info"]

#: The most a single POST may carry. Generous for a list of clicked points, small
#: enough that a runaway request cannot fill memory.
MAX_BODY_BYTES = 4 * 1024 * 1024

#: The Bonjour service type the app looks for. Matches ``NSBonjourServices`` in
#: ``ios/project.yml`` once the app side lands; change both or neither.
SERVICE_TYPE = "_vividhome._tcp.local."


class StoreHandler(SimpleHTTPRequestHandler):
    """Serves the store read-only, plus ``POST /save`` when writable."""

    def __init__(self, *args, root: Path, writable: bool = True, **kwargs):
        self._root = root
        self._writable = writable
        super().__init__(*args, directory=str(root), **kwargs)

    def log_message(self, format: str, *args) -> None:
        # The default logs every request to stderr, which buries the CLI's output.
        pass

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/index.json":
            self._send_json(build_index(self._root))
            return
        if path == "/_vividhome/ping":
            self._send_json({"vividhome": __version__, "store": self._root.name})
            return
        super().do_GET()

    def do_POST(self) -> None:
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

    def _send_json(self, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(200)
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


def make_server(
    store: str | Path, *, host: str = "127.0.0.1", port: int = 0, writable: bool = True
):
    """Build a server rooted at the store. Port 0 asks the OS for a free one."""
    root = Path(store).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return ThreadingHTTPServer((host, port), partial(StoreHandler, root=root, writable=writable))


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
    server = make_server(root, host=host, port=port, writable=not lan)
    actual = server.server_address[1]

    advertisement: Advertisement | None = None
    if lan:
        addresses = lan_addresses()
        print(f"serving {root} read-only on the network")
        for address in addresses or ["<no network address found>"]:
            print(f"  http://{address}:{actual}/{open_path}")
        print("  anyone on this network can read the store; nothing on it can write")
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
