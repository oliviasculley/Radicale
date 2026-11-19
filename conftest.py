# This file is part of Radicale - CalDAV and CardDAV server
# Copyright © 2026-2026 oliviasculley <olivia@sculley.dev>
#
# This library is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Radicale.  If not, see <http://www.gnu.org/licenses/>.

"""Run independent pytest cases at the same time on one asyncio gate.

The ``py`` tox env starts four worker processes, one per vCPU on the
default GitHub-hosted ``ubuntu-26.04`` runner. Two async cases meet at
a gate that answers only while both are inside the test. A sequential
session never gets that answer, so those cases fail.
"""

import asyncio
import inspect
import os
import threading
from typing import Any, Callable, List, Optional

import pytest

_LEFT = "test_async_session_overlaps_left"
_RIGHT = "test_async_session_overlaps_right"
_OVERLAP_NAMES = (_LEFT, _RIGHT)
# Hang guard only. Passing requires the peer's name, not a duration.
_OVERLAP_TIMEOUT_S = 120
_overlap_passed: List[str] = []


class _OverlapGate:
    """Answer two clients only once both are waiting."""

    def __init__(self) -> None:
        self._pending: List[Any] = []

    async def handle(
            self, reader: asyncio.StreamReader,
            writer: asyncio.StreamWriter) -> None:
        loop = asyncio.get_running_loop()
        future: asyncio.Future = loop.create_future()
        try:
            raw = await reader.readline()
            name = raw.decode().strip()
            self._pending.append((name, writer, future))
            if len(self._pending) >= 2:
                batch = self._pending[:2]
                del self._pending[:2]
                names = " ".join(item[0] for item in batch)
                payload = ("together %s\n" % names).encode()
                for _name, peer, fut in batch:
                    peer.write(payload)
                    await peer.drain()
                    if not fut.done():
                        fut.set_result(payload)
            await future
        except Exception:
            if not future.done():
                future.cancel()
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass


def _worker_count(config: pytest.Config) -> int:
    num = getattr(config.option, "numprocesses", None)
    if isinstance(num, int):
        return num
    if isinstance(num, str) and num.isdigit():
        return int(num)
    return 0


def _start_gate() -> int:
    ready = threading.Event()
    holder: dict = {}

    def _thread() -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        gate = _OverlapGate()

        async def _serve() -> None:
            server = await asyncio.start_server(
                gate.handle, "127.0.0.1", 0)
            sockets = server.sockets
            if not sockets:
                raise RuntimeError("overlap gate has no socket")
            holder["server"] = server
            holder["port"] = sockets[0].getsockname()[1]
            ready.set()
            async with server:
                await server.serve_forever()

        try:
            loop.run_until_complete(_serve())
        except asyncio.CancelledError:
            pass

    thread = threading.Thread(target=_thread, name="radicale-overlap-gate")
    thread.daemon = True
    thread.start()
    if not ready.wait(10):
        raise RuntimeError("overlap gate did not bind")
    return int(holder["port"])


def pytest_configure(config: pytest.Config) -> None:
    workerinput = getattr(config, "workerinput", None)
    if workerinput is not None:
        port = workerinput.get("radicale_overlap_port")
        if port:
            os.environ["RADICALE_OVERLAP_PORT"] = str(port)
        return
    if os.environ.get("RADICALE_PYTEST_ASYNC") == "0":
        return
    if _worker_count(config) < 2:
        return
    config._radicale_overlap_port = _start_gate()  # type: ignore[attr-defined]


def pytest_configure_node(node: Any) -> None:
    port = getattr(node.config, "_radicale_overlap_port", None)
    if port is not None:
        node.workerinput["radicale_overlap_port"] = str(port)


def pytest_collection_modifyitems(
        config: pytest.Config, items: List[pytest.Item]) -> None:
    """Put the two overlap cases on different workers, or drop them.

    With ``--maxschedchunk=1``, xdist still hands each worker two cases
    at the start, in collection order. Index 0 and index 2 are the first
    case on two workers, so both are in progress together.
    """
    if os.environ.get("RADICALE_PYTEST_ASYNC") == "0":
        dropped = [item for item in items if item.name in _OVERLAP_NAMES]
        if dropped:
            config.hook.pytest_deselected(items=dropped)
        items[:] = [item for item in items if item.name not in _OVERLAP_NAMES]
        return
    left = [item for item in items if item.name == _LEFT]
    right = [item for item in items if item.name == _RIGHT]
    rest = [item for item in items if item.name not in _OVERLAP_NAMES]
    if left and right and len(rest) >= 2:
        items[:] = [left[0], rest[0], right[0], *rest[1:]]


@pytest.hookimpl(tryfirst=True)
def pytest_pyfunc_call(pyfuncitem: pytest.Function) -> Optional[bool]:
    func: Callable[..., Any] = pyfuncitem.obj
    if not inspect.iscoroutinefunction(func):
        return None
    kwargs = {
        name: pyfuncitem.funcargs[name]
        for name in inspect.signature(func).parameters
    }
    asyncio.run(func(**kwargs))
    return True


def pytest_runtest_logreport(report: pytest.TestReport) -> None:
    if report.when != "call" or not report.passed:
        return
    if "test_async_session_overlaps_" in report.nodeid:
        _overlap_passed.append(report.nodeid)


def pytest_terminal_summary(
        terminalreporter: Any, exitstatus: int,
        config: pytest.Config) -> None:
    if getattr(config, "workerinput", None) is not None:
        return
    if len(_overlap_passed) >= 2:
        terminalreporter.write_line(
            "async overlap: independent cases were in progress together "
            "(%d)" % len(_overlap_passed))
