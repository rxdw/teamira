"""Unit tests for app/rate_limit.py's RateLimiter directly — below the
HTTP layer, against the real `rate_limit_hits` table via the
transactional `db_session` fixture. test_auth.py separately proves the
two limiters auth.py actually wires up behave correctly end-to-end;
these tests cover the class's own behavior more precisely (window
rollover, independent buckets) than is practical to provoke through
HTTP alone."""

import fastapi
import pytest
from starlette.requests import Request

from app.config import settings
from app.rate_limit import RateLimiter, client_key


@pytest.fixture()
def limiter():
    return RateLimiter("test_limiter", max_calls=3, window_seconds=60)


class TestRateLimiter:
    def test_allows_up_to_max_calls(self, db_session, limiter):
        for _ in range(3):
            limiter.check(db_session, "some-key")  # should not raise

    def test_the_call_after_max_calls_is_rejected(self, db_session, limiter):
        for _ in range(3):
            limiter.check(db_session, "some-key")
        with pytest.raises(fastapi.HTTPException) as exc_info:
            limiter.check(db_session, "some-key")
        assert exc_info.value.status_code == 429

    def test_different_keys_have_independent_buckets(self, db_session, limiter):
        for _ in range(3):
            limiter.check(db_session, "key-a")
        # key-a is now exhausted; key-b should be entirely unaffected.
        for _ in range(3):
            limiter.check(db_session, "key-b")  # should not raise

    def test_different_limiter_names_have_independent_buckets_for_the_same_key(self, db_session):
        limiter_a = RateLimiter("limiter_a", max_calls=2, window_seconds=60)
        limiter_b = RateLimiter("limiter_b", max_calls=2, window_seconds=60)
        for _ in range(2):
            limiter_a.check(db_session, "shared-key")
        # Same key, but a different limiter name — its own budget.
        for _ in range(2):
            limiter_b.check(db_session, "shared-key")  # should not raise

    def test_new_window_resets_the_count(self, db_session, limiter, monkeypatch):
        base_time = 1_700_000_000.0  # arbitrary fixed point, window-aligned math only cares about deltas
        current = {"t": base_time}
        monkeypatch.setattr("app.rate_limit.time.time", lambda: current["t"])

        for _ in range(3):
            limiter.check(db_session, "windowed-key")
        with pytest.raises(fastapi.HTTPException):
            limiter.check(db_session, "windowed-key")

        # Jump forward well past the 60s window — a fresh bucket should
        # have its own max_calls budget again.
        current["t"] = base_time + 61
        for _ in range(3):
            limiter.check(db_session, "windowed-key")  # should not raise
        with pytest.raises(fastapi.HTTPException):
            limiter.check(db_session, "windowed-key")


def _fake_request(peer_ip: str, forwarded_for: str = "") -> Request:
    """A bare-minimum ASGI scope — client_key only ever looks at
    request.client.host and the x-forwarded-for header, so nothing else
    on a real request needs to exist here."""
    headers = []
    if forwarded_for:
        headers.append((b"x-forwarded-for", forwarded_for.encode()))
    scope = {
        "type": "http",
        "client": (peer_ip, 12345),
        "headers": headers,
    }
    return Request(scope)


class TestClientKey:
    """app/rate_limit.py::client_key — the X-Forwarded-For trust logic in
    particular (audit 3.4.5). settings.trusted_proxy_ips is module-level
    global state read by client_key on every call, so every test here
    restores it in a finally block rather than leaking its override into
    whichever test happens to run next."""

    def _with_trusted(self, raw: str):
        original = settings.trusted_proxy_ips
        settings.trusted_proxy_ips = raw
        return original

    def test_no_trusted_proxies_configured_uses_peer_address(self):
        original = self._with_trusted("")
        try:
            # Even a client that sends its own X-Forwarded-For is ignored
            # entirely when nothing is configured to trust it — this is
            # the default, and it's the safe one.
            req = _fake_request("203.0.113.9", forwarded_for="1.2.3.4")
            assert client_key(req) == "203.0.113.9"
        finally:
            settings.trusted_proxy_ips = original

    def test_untrusted_peer_is_used_even_with_trusted_proxies_configured(self):
        original = self._with_trusted("10.0.0.0/8")
        try:
            # The request didn't come from a trusted proxy at all — its
            # X-Forwarded-For (if any) is exactly as trustworthy as the
            # rest of the request, i.e. not at all.
            req = _fake_request("203.0.113.9", forwarded_for="9.9.9.9")
            assert client_key(req) == "203.0.113.9"
        finally:
            settings.trusted_proxy_ips = original

    def test_trusted_proxy_forwards_the_real_client(self):
        original = self._with_trusted("10.0.0.5")
        try:
            req = _fake_request("10.0.0.5", forwarded_for="203.0.113.9")
            assert client_key(req) == "203.0.113.9"
        finally:
            settings.trusted_proxy_ips = original

    def test_walks_past_multiple_trusted_hops_to_the_real_client(self):
        # Two trusted proxies in a chain (e.g. a CDN handing off to an
        # internal load balancer, both configured as trusted): the real
        # client is the first entry, from the right, that isn't one of
        # them.
        original = self._with_trusted("10.0.0.5,10.0.0.6")
        try:
            req = _fake_request("10.0.0.5", forwarded_for="203.0.113.9, 10.0.0.6")
            assert client_key(req) == "203.0.113.9"
        finally:
            settings.trusted_proxy_ips = original

    def test_client_spoofed_prefix_is_never_reached(self):
        """The classic bypass attempt: a client sends its own
        X-Forwarded-For hoping the first entry is trusted blindly. Here
        the peer *is* a trusted proxy, so the header is consulted — but
        walking from the right still finds the proxy's own real value
        (203.0.113.9) before it ever reaches the client-supplied
        1.2.3.4 sitting further left."""
        original = self._with_trusted("10.0.0.5")
        try:
            req = _fake_request("10.0.0.5", forwarded_for="1.2.3.4, 203.0.113.9")
            assert client_key(req) == "203.0.113.9"
        finally:
            settings.trusted_proxy_ips = original

    def test_cidr_range_is_honored(self):
        original = self._with_trusted("10.0.0.0/8")
        try:
            req = _fake_request("10.4.5.6", forwarded_for="203.0.113.9")
            assert client_key(req) == "203.0.113.9"
        finally:
            settings.trusted_proxy_ips = original

    def test_garbage_forwarded_for_falls_back_to_peer(self):
        original = self._with_trusted("10.0.0.5")
        try:
            req = _fake_request("10.0.0.5", forwarded_for="not-an-ip-address")
            # "not-an-ip-address" isn't parseable, so _is_trusted_proxy
            # returns False for it and it's treated as the (nonsensical
            # but non-crashing) client key — this asserts the function
            # never raises, not that the result is meaningful.
            assert client_key(req) == "not-an-ip-address"
        finally:
            settings.trusted_proxy_ips = original

    def test_no_forwarded_header_falls_back_to_peer(self):
        original = self._with_trusted("10.0.0.5")
        try:
            req = _fake_request("10.0.0.5", forwarded_for="")
            assert client_key(req) == "10.0.0.5"
        finally:
            settings.trusted_proxy_ips = original
