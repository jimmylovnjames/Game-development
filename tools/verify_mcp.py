#!/usr/bin/env python3
"""Handshake with every MCP server in .mcp.json and list the tools each exposes.

Claude only surfaces project-scope servers after an interactive approval, which
makes it easy to *think* a server works when it has never actually started. This
speaks JSON-RPC to each one directly, so a green line here means the server
really launched and really answered `tools/list`.

Usage:
    python3 tools/verify_mcp.py [--json] [--config .mcp.json]
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

PROTOCOL_VERSION = "2024-11-05"
CLIENT_INFO = {"name": "neonwastes-verify", "version": "1.0.0"}


def _init_params() -> dict:
    return {
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": CLIENT_INFO,
    }


def probe_stdio(name: str, spec: dict, timeout: float = 45.0) -> dict:
    """Launch a stdio server, initialize, and ask for its tool list.

    stdin is deliberately held open and stdout drained on a reader thread.
    Writing every frame and closing stdin up front (subprocess.communicate) looks
    like a client disconnect to servers that track connection state, and they
    shut down instead of answering.
    """
    env = dict(os.environ)
    env.update(spec.get("env") or {})
    argv = [spec["command"], *spec.get("args", [])]

    try:
        proc = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True,
            bufsize=1,
        )
    except FileNotFoundError:
        return {"name": name, "ok": False, "error": f"command not found: {argv[0]}"}

    lines: list[str] = []
    reader = threading.Thread(target=_drain, args=(proc.stdout, lines), daemon=True)
    reader.start()
    errs: list[str] = []
    threading.Thread(target=_drain, args=(proc.stderr, errs), daemon=True).start()

    def send(payload: dict) -> None:
        proc.stdin.write(json.dumps(payload) + "\n")
        proc.stdin.flush()

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": _init_params()})
        if not _await_id(lines, 1, proc, timeout):
            raise TimeoutError("no response to initialize")

        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        if not _await_id(lines, 2, proc, timeout):
            raise TimeoutError("no response to tools/list")
    except (TimeoutError, BrokenPipeError, OSError) as exc:
        _shutdown(proc)
        return {"name": name, "ok": False, "error": str(exc),
                "stderr": "".join(errs).strip()[-400:]}

    _shutdown(proc)
    return _read_frames(name, "".join(lines), "".join(errs).strip()[-400:])


def _drain(stream, sink: list) -> None:
    try:
        for line in stream:
            sink.append(line)
    except (ValueError, OSError):
        pass


def _await_id(lines: list, want_id: int, proc: subprocess.Popen, timeout: float) -> bool:
    """Wait until a JSON-RPC frame carrying `want_id` shows up on stdout."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for line in list(lines):
            stripped = line.strip()
            if not stripped.startswith("{"):
                continue
            try:
                msg = json.loads(stripped)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == want_id:
                return True
        if proc.poll() is not None:
            return False
        time.sleep(0.05)
    return False


def _shutdown(proc: subprocess.Popen) -> None:
    try:
        if proc.stdin and not proc.stdin.closed:
            proc.stdin.close()
    except OSError:
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def _read_frames(name: str, stdout: str, stderr: str) -> dict:
    """Pull the initialize + tools/list responses out of a stdio transcript."""
    server_info: dict = {}
    tools: list[str] = []
    saw_response = False

    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("id") == 1 and "result" in msg:
            saw_response = True
            server_info = msg["result"].get("serverInfo", {})
        elif msg.get("id") == 2 and "result" in msg:
            saw_response = True
            tools = [t.get("name", "?") for t in msg["result"].get("tools", [])]
        elif "error" in msg:
            return {"name": name, "ok": False,
                    "error": json.dumps(msg["error"])[:300], "stderr": stderr}

    if not saw_response:
        return {"name": name, "ok": False,
                "error": "no JSON-RPC response on stdout", "stderr": stderr}

    return {
        "name": name,
        "ok": True,
        "server": f"{server_info.get('name', '?')} {server_info.get('version', '')}".strip(),
        "tools": sorted(tools),
    }


def probe_http(name: str, spec: dict, timeout: float = 30.0) -> dict:
    """Initialize over streamable-HTTP, then list tools on the same session."""
    url = spec["url"]
    headers = {
        "Content-Type": "application/json",
        # Streamable HTTP servers reject a request that will not take SSE back.
        "Accept": "application/json, text/event-stream",
    }

    try:
        init_body, session = _http_rpc(
            url, headers, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                           "params": _init_params()}, timeout,
        )
    except (urllib.error.URLError, OSError) as exc:
        return {"name": name, "ok": False, "error": f"{type(exc).__name__}: {exc}"}

    if session:
        headers["mcp-session-id"] = session

    # The spec requires this notification before any other call on the session.
    try:
        _http_rpc(url, headers,
                  {"jsonrpc": "2.0", "method": "notifications/initialized"}, timeout)
        list_body, _ = _http_rpc(
            url, headers,
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}, timeout,
        )
    except (urllib.error.URLError, OSError) as exc:
        return {"name": name, "ok": False, "error": f"{type(exc).__name__}: {exc}"}

    info = (init_body.get("result") or {}).get("serverInfo", {})
    tools = [t.get("name", "?") for t in (list_body.get("result") or {}).get("tools", [])]
    return {
        "name": name,
        "ok": True,
        "server": f"{info.get('name', '?')} {info.get('version', '')}".strip(),
        "tools": sorted(tools),
    }


def _http_rpc(url: str, headers: dict, payload: dict, timeout: float):
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(), headers=headers, method="POST"
    )
    # Never route loopback through an outbound proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=timeout) as resp:
        session = resp.headers.get("mcp-session-id")
        raw = resp.read().decode(errors="replace")
    return _parse_maybe_sse(raw), session


def _parse_maybe_sse(raw: str) -> dict:
    """Streamable HTTP may answer with plain JSON or a one-event SSE stream."""
    raw = raw.strip()
    if not raw:
        return {}
    if raw.startswith("{"):
        return json.loads(raw)
    for line in raw.splitlines():
        if line.startswith("data:"):
            chunk = line[5:].strip()
            if chunk.startswith("{"):
                return json.loads(chunk)
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=".mcp.json")
    parser.add_argument("--json", action="store_true", help="emit machine-readable output")
    args = parser.parse_args()

    try:
        with open(args.config) as handle:
            servers = json.load(handle).get("mcpServers", {})
    except FileNotFoundError:
        print(f"no such config: {args.config}", file=sys.stderr)
        return 2

    if not servers:
        print(f"{args.config} declares no MCP servers", file=sys.stderr)
        return 2

    results = []
    for name, spec in servers.items():
        kind = spec.get("type") or ("http" if "url" in spec else "stdio")
        results.append(probe_http(name, spec) if kind == "http" else probe_stdio(name, spec))

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        for result in results:
            if result["ok"]:
                print(f"  ok    {result['name']:<14} {result['server']} "
                      f"— {len(result['tools'])} tools")
                print(f"        {', '.join(result['tools'])}")
            else:
                print(f"  FAIL  {result['name']:<14} {result['error']}")
                if result.get("stderr"):
                    print(f"        stderr: {result['stderr']}")

    failed = sum(1 for r in results if not r["ok"])
    print()
    print(f"MCP: {len(results) - failed}/{len(results)} server(s) responded.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
