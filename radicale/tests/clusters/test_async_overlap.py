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

"""Fail unless two independent cases are in progress together.

The session gate replies ``together`` only after both cases have
connected and are waiting. One case running alone never gets that
reply. The timeout only stops a sequential session from hanging.
"""

import asyncio
import os

_TIMEOUT_S = 120


async def _meet(name: str) -> bytes:
    port = os.environ.get("RADICALE_OVERLAP_PORT")
    assert port, "independent cases are not running concurrently"
    reader, writer = await asyncio.wait_for(
        asyncio.open_connection("127.0.0.1", int(port)), _TIMEOUT_S)
    writer.write(("%s\n" % name).encode())
    await writer.drain()
    try:
        line = await asyncio.wait_for(reader.readline(), _TIMEOUT_S)
    finally:
        writer.close()
        await writer.wait_closed()
    return line


def _peers_are_together(line: bytes) -> None:
    parts = line.split()
    assert parts[:1] == [b"together"], line
    assert b"left" in parts, line
    assert b"right" in parts, line


async def test_async_session_overlaps_left() -> None:
    _peers_are_together(await _meet("left"))


async def test_async_session_overlaps_right() -> None:
    _peers_are_together(await _meet("right"))
