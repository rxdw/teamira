"""app/main.py's `_insecure_defaults` + `_enforce_startup_security`, the
ENVIRONMENT=production boot guard built on top of it (audit follow-up,
P1 item 4).

Both are pure-ish (read a settings-shaped object, only I/O is logging),
kept as their own functions specifically so this file can exercise the
guard directly without also running on_startup's create_all()/
run_migrations()/seeding+purge block — that's already exercised once per
test session by conftest.py, and re-running it per test here would just
duplicate that slowly.
"""

from app.config import settings
from app.main import _enforce_startup_security, _insecure_defaults
import pytest


class _FakeSettings:
    """Just enough of Settings' shape for _insecure_defaults to read."""

    def __init__(self, jwt_secret="a-real-random-secret", email_backend="smtp"):
        self.jwt_secret = jwt_secret
        self.email_backend = email_backend


class TestInsecureDefaults:
    def test_no_problems_when_both_are_set_properly(self):
        assert _insecure_defaults(_FakeSettings()) == []

    def test_flags_default_jwt_secret(self):
        problems = _insecure_defaults(_FakeSettings(jwt_secret="change-me"))
        assert len(problems) == 1
        assert "change-me" in problems[0]

    def test_flags_non_smtp_email_backend(self):
        problems = _insecure_defaults(_FakeSettings(email_backend="console"))
        assert len(problems) == 1
        assert "console" in problems[0]

    def test_email_backend_check_is_case_and_whitespace_insensitive(self):
        # Same tolerance the rest of the app gives config strings
        # elsewhere (see e.g. moderation.py's status comparisons) —
        # "SMTP" or " smtp " in .env shouldn't trip a false positive.
        assert _insecure_defaults(_FakeSettings(email_backend=" SMTP ")) == []

    def test_flags_both_independently(self):
        problems = _insecure_defaults(
            _FakeSettings(jwt_secret="change-me", email_backend="console")
        )
        assert len(problems) == 2


class TestEnforceStartupSecurity:
    def test_production_with_default_jwt_secret_refuses_to_boot(self, monkeypatch):
        monkeypatch.setattr(settings, "environment", "production")
        monkeypatch.setattr(settings, "jwt_secret", "change-me")
        monkeypatch.setattr(settings, "email_backend", "smtp")
        with pytest.raises(RuntimeError, match="change-me"):
            _enforce_startup_security(settings)

    def test_development_with_default_jwt_secret_does_not_raise(self, monkeypatch):
        # The whole point of ENVIRONMENT defaulting to "development": the
        # exact same insecure config that's fatal in production is only
        # ever logged here — this must stay true or local dev breaks.
        monkeypatch.setattr(settings, "environment", "development")
        monkeypatch.setattr(settings, "jwt_secret", "change-me")
        monkeypatch.setattr(settings, "email_backend", "smtp")
        _enforce_startup_security(settings)  # must not raise

    def test_production_with_real_secrets_does_not_raise(self, monkeypatch):
        monkeypatch.setattr(settings, "environment", "production")
        monkeypatch.setattr(settings, "jwt_secret", "a-real-random-secret-value")
        monkeypatch.setattr(settings, "email_backend", "smtp")
        _enforce_startup_security(settings)  # must not raise

    def test_production_with_only_email_backend_wrong_raises_with_that_detail(self, monkeypatch):
        monkeypatch.setattr(settings, "environment", "production")
        monkeypatch.setattr(settings, "jwt_secret", "a-real-random-secret-value")
        monkeypatch.setattr(settings, "email_backend", "console")
        with pytest.raises(RuntimeError, match="console"):
            _enforce_startup_security(settings)
