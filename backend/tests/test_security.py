"""Unit tests for app/security.py — no DB, no HTTP, just the hashing and
JWT functions in isolation. Everything else (auth.py's actual /register
and /login behavior) lives in test_auth.py instead."""

import time

import pytest
from jose import jwt

from app.config import settings
from app.security import create_access_token, decode_access_token, hash_password, verify_password


class TestPasswordHashing:
    def test_hash_is_not_the_plaintext(self):
        hashed = hash_password("correct-horse-battery")
        assert hashed != "correct-horse-battery"

    def test_correct_password_verifies(self):
        hashed = hash_password("correct-horse-battery")
        assert verify_password("correct-horse-battery", hashed) is True

    def test_wrong_password_does_not_verify(self):
        hashed = hash_password("correct-horse-battery")
        assert verify_password("not-the-password", hashed) is False

    def test_hashing_is_salted(self):
        # Same input, two different calls -> different hashes (bcrypt
        # generates a fresh random salt each time via gensalt()) — both
        # still have to verify against the original password though.
        a = hash_password("same-password")
        b = hash_password("same-password")
        assert a != b
        assert verify_password("same-password", a)
        assert verify_password("same-password", b)

    def test_password_over_72_bytes_is_rejected(self):
        # bcrypt's own hard limit — see _MAX_PASSWORD_BYTES's comment.
        too_long = "a" * 73
        with pytest.raises(ValueError):
            hash_password(too_long)

    def test_password_at_exactly_72_bytes_is_accepted(self):
        exactly_72 = "a" * 72
        hashed = hash_password(exactly_72)
        assert verify_password(exactly_72, hashed)

    def test_verify_against_malformed_hash_returns_false_not_raise(self):
        # verify_password is also called with a hash that was never
        # produced by hash_password in one specific spot — the shared
        # dummy hash in auth.py's login() for a username that doesn't
        # exist. Real hashes are always well-formed, but this should
        # still fail closed rather than raise for any garbage input.
        assert verify_password("anything", "not-a-real-bcrypt-hash") is False


class TestAccessTokens:
    def test_roundtrip_returns_the_same_subject(self):
        # decode_access_token now returns the full claim set (sub, typ,
        # ver, jti, iat, exp) rather than a bare subject string — it has
        # to, so callers can check token_version for revocation and typ
        # to reject a refresh token presented as an access token (see
        # app/deps.py::get_current_user and this module's own docstring).
        # `sub` is still exactly what was passed to create_access_token.
        token = create_access_token("user-123")
        claims = decode_access_token(token)
        assert claims["sub"] == "user-123"

    def test_garbage_token_decodes_to_none(self):
        assert decode_access_token("not.a.jwt") is None

    def test_token_signed_with_a_different_secret_is_rejected(self):
        forged = jwt.encode({"sub": "user-123"}, "some-other-secret", algorithm=settings.jwt_algorithm)
        assert decode_access_token(forged) is None

    def test_expired_token_is_rejected(self):
        # Encoded directly with jose rather than via create_access_token,
        # so the expiry can be forced into the past instead of waiting
        # out settings.jwt_expire_minutes.
        expired = jwt.encode(
            {"sub": "user-123", "exp": int(time.time()) - 60},
            settings.jwt_secret,
            algorithm=settings.jwt_algorithm,
        )
        assert decode_access_token(expired) is None

    def test_token_with_no_algorithm_match_is_rejected(self):
        # decode_access_token pins algorithms=[settings.jwt_algorithm]
        # explicitly (see that function) rather than trusting whatever
        # algorithm the token claims — this confirms a token signed with
        # a different algorithm's secret-as-key doesn't slip through.
        wrong_alg_token = jwt.encode({"sub": "user-123"}, settings.jwt_secret, algorithm="HS512")
        assert decode_access_token(wrong_alg_token) is None
