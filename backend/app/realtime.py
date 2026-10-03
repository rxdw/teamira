"""Realtime push for the three session types that used to be polled on
a client-side `Timer.periodic` — co-viewing "vote together" rounds
(co_view_vote.py), "vote it out" polls (co_view_poll.py), and Watch
Together's network mode (together.py). Each of those had a mobile
screen hitting `GET .../{id}` every couple of seconds purely to find
out whether anything had changed; this replaces that with a
WebSocket the server pushes to instead.

**Why this needs Postgres LISTEN/NOTIFY and not just an in-process
dict of open sockets.** backend/Dockerfile's own `UVICORN_WORKERS` can
run more than one worker process (see its comment on that variable),
and nothing pins a given link's two participants to the same worker —
partner A's vote can easily land on a different process than the one
holding partner B's open socket. An in-memory registry only ever sees
the process it lives in, so it would silently work in local dev
(`UVICORN_WORKERS=1`, today's default) and silently *stop* working the
moment a deployment turns that up. Postgres NOTIFY already reaches
every LISTENing connection across every process talking to the same
database — this app already requires Postgres, so this adds no new
moving part (no Redis, no message broker) to get the same guarantee.

**Shape.** A mutation calls `publish(db, topic)` in the *same*
transaction as its own change, right before that transaction's own
`db.commit()` — NOTIFY only actually reaches anyone once that
transaction commits, so a rolled-back vote never fires a phantom
update. Each worker process runs exactly one background thread (see
`Listener`, started from main.py's on_startup) holding one dedicated
LISTEN connection; when a notification arrives there, it wakes every
local websocket connection subscribed to that topic *in this process*
via `Hub.publish_local` — cheap, in-memory, asyncio.Queue-based. A
websocket handler that wakes just re-reads its own row from the
database and sends the current state down the wire — the NOTIFY
payload only ever carries the topic string (e.g. "vote:<session id>"),
never the state itself, so there's nothing that can get out of sync
between what NOTIFY said and what's actually in the database, and no
risk of hitting Postgres's 8000-byte NOTIFY payload cap.
"""
from __future__ import annotations

import asyncio
import contextlib
import logging
import select
import threading
from typing import Callable, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session
from starlette.websockets import WebSocket, WebSocketDisconnect

from app.database import engine

logger = logging.getLogger("uvicorn.error")

CHANNEL = "seenly_realtime"

# Ceiling on how long a websocket loop ever waits before refetching on
# its own, even with no NOTIFY and no caller-supplied earlier wake-up
# (see run_ws_loop's `wait_seconds`) — a safety net against a missed
# NOTIFY (a LISTEN connection reconnecting after a blip, say), not the
# normal way updates arrive.
DEFAULT_HEARTBEAT = 30.0


def topic_for(kind: str, session_id: str) -> str:
    """`kind` is a short tag per session type ("vote", "poll",
    "together") — kept short since it round-trips through a Postgres
    NOTIFY payload as-is."""
    return f"{kind}:{session_id}"


def publish(db: Session, topic: str) -> None:
    """Call this from inside a mutating endpoint, in the same
    transaction as the change and before that transaction's own
    `db.commit()` — see this module's docstring for why the ordering
    matters. `pg_notify` is a plain SQL function, not DDL/DML, so this
    doesn't need its own commit and doesn't disturb whatever the caller
    was about to do with its own."""
    db.execute(text("SELECT pg_notify(:channel, :topic)"), {"channel": CHANNEL, "topic": topic})


class Hub:
    """Per-process registry of who's waiting on which topic. On its own
    this only ever sees NOTIFYs and subscribers within one worker
    process — see Listener below for the piece that bridges it across
    every process sharing this database."""

    def __init__(self) -> None:
        self._topics: dict[str, set[asyncio.Queue]] = {}
        self._lock = threading.Lock()

    def subscribe(self, topic: str) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=1)
        with self._lock:
            self._topics.setdefault(topic, set()).add(q)
        return q

    def unsubscribe(self, topic: str, q: asyncio.Queue) -> None:
        with self._lock:
            subs = self._topics.get(topic)
            if subs is None:
                return
            subs.discard(q)
            if not subs:
                self._topics.pop(topic, None)

    def publish_local(self, topic: str) -> None:
        """Runs on the event loop thread (Listener hands it to
        `loop.call_soon_threadsafe`) — wakes every local subscriber for
        `topic`. A queue that already has an unconsumed wake-up sitting
        in it (maxsize=1 — `put_nowait` raises QueueFull rather than
        blocking or growing) doesn't need a second one: the handler is
        going to re-read the current row from the database regardless
        of how many notifications arrived, so two landing close
        together just collapse into a single refetch, the same way two
        polls landing close together always did."""
        with self._lock:
            subs = list(self._topics.get(topic, ()))
        for q in subs:
            with contextlib.suppress(asyncio.QueueFull):
                q.put_nowait(None)


hub = Hub()


class Listener:
    """One dedicated, autocommit LISTEN connection per worker process,
    run on a plain background thread rather than as an asyncio task:
    psycopg2's own way to wait for a notification is a blocking
    `select.select` on the connection's socket, not an awaitable.
    Started from main.py's on_startup with the running event loop (so
    it has somewhere to hand notifications off to) and stopped on
    shutdown.
    """

    def __init__(self) -> None:
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._conn = None

    def start(self, loop: asyncio.AbstractEventLoop) -> None:
        self._loop = loop
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="pg-notify-listener", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        conn = self._conn
        if conn is not None:
            with contextlib.suppress(Exception):
                conn.close()
        thread = self._thread
        if thread is not None:
            thread.join(timeout=2)

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                self._listen_forever()
            except Exception:
                if self._stop.is_set():
                    return
                logger.exception("pg notify listener dropped — reconnecting in 3s")
                self._stop.wait(3)

    def _listen_forever(self) -> None:
        # A raw DBAPI connection off the same engine everything else in
        # this app already talks to, detached from the pool so it's
        # never handed back and reused for an ordinary request — this
        # one is held open indefinitely and put in LISTEN mode, which
        # would be actively wrong for any other caller to check out.
        fairy = engine.raw_connection()
        fairy.detach()
        conn = fairy.connection
        conn.autocommit = True
        self._conn = conn
        try:
            cur = conn.cursor()
            cur.execute(f"LISTEN {CHANNEL};")
            cur.close()
            logger.info("pg notify listener: LISTEN %s", CHANNEL)
            while not self._stop.is_set():
                # 5s poll of the socket, not the channel: this is just
                # so the loop notices `_stop` in a timely way, not how
                # notifications are discovered — those come back
                # instantly the moment select() reports the socket
                # readable.
                if not select.select([conn], [], [], 5)[0]:
                    continue
                conn.poll()
                while conn.notifies:
                    notify = conn.notifies.pop(0)
                    loop = self._loop
                    if loop is not None:
                        loop.call_soon_threadsafe(hub.publish_local, notify.payload)
        finally:
            with contextlib.suppress(Exception):
                conn.close()
            self._conn = None


listener = Listener()


async def run_ws_loop(
    websocket: WebSocket,
    topic: str,
    fetch: Callable[[], Optional[str]],
    *,
    wait_seconds: float | Callable[[], float] = DEFAULT_HEARTBEAT,
) -> None:
    """Shared pump behind every session websocket in this app: send the
    current state right away, then block until either a local wake-up
    for `topic` arrives (a NOTIFY landed — see Hub/Listener above) or
    `wait_seconds` elapses, whichever comes first, and refetch/resend
    either way. Also watches for the client disconnecting, so a socket
    nobody's listening to anymore doesn't sit around holding its
    subscription forever.

    `fetch` is a zero-argument callable returning the JSON string to
    send, or None once the session itself is gone (ended/deleted) —
    that ends the loop cleanly (a normal close, not an error) instead
    of trying to send an update for a row that no longer exists.
    `wait_seconds` can be a plain number (co_view_vote, together — a
    pure safety net, since nothing about those ever changes on a
    schedule of its own) or a zero-argument callable returning a fresh
    number each iteration (co_view_poll, which also needs to wake up
    right around its own deadline even if nobody casts another vote
    before then).

    Caller is expected to have already accepted the connection and
    authenticated the caller before calling this — this only pumps
    updates, it doesn't authenticate them.
    """
    queue = hub.subscribe(topic)
    try:
        payload = fetch()
        if payload is None:
            await websocket.close(code=4404)
            return
        await websocket.send_text(payload)

        # A bare `await websocket.receive_text()` is only here to
        # notice a client disconnect promptly — this app has nothing
        # for the client to say once connected, everything flows
        # server -> client. Raises WebSocketDisconnect the moment the
        # client actually goes away, which is exactly the signal this
        # loop needs to stop.
        async def _watch_for_disconnect() -> None:
            while True:
                await websocket.receive_text()

        disconnect_task = asyncio.ensure_future(_watch_for_disconnect())
        try:
            while True:
                timeout = wait_seconds() if callable(wait_seconds) else wait_seconds
                wake_task = asyncio.ensure_future(queue.get())
                done, _pending = await asyncio.wait(
                    {wake_task, disconnect_task},
                    timeout=timeout,
                    return_when=asyncio.FIRST_COMPLETED,
                )
                if disconnect_task in done:
                    wake_task.cancel()
                    disconnect_task.result()  # re-raises WebSocketDisconnect
                    return
                if wake_task not in done:
                    wake_task.cancel()  # timed out — refetch anyway, on schedule

                payload = fetch()
                if payload is None:
                    await websocket.close(code=1000)
                    return
                await websocket.send_text(payload)
        finally:
            disconnect_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, WebSocketDisconnect, Exception):
                await disconnect_task
    except WebSocketDisconnect:
        pass
    finally:
        hub.unsubscribe(topic, queue)
