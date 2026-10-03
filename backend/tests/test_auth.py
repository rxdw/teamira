"""Integration tests for app/routers/auth.py, through the real HTTP
layer (TestClient) rather than calling the route functions directly —
this is what actually proves request validation, status codes, and
routing are wired up correctly, not just the logic inside them."""


class TestRegister:
    def test_register_returns_a_usable_token(self, client):
        resp = client.post(
            "/auth/register",
            json={"username": "alice_test", "password": "correct-horse-battery"},
        )
        assert resp.status_code == 201
        body = resp.json()
        assert body["token_type"] == "bearer"
        assert isinstance(body["access_token"], str) and body["access_token"]

        # The token has to actually work, not just be present.
        me = client.get("/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"})
        assert me.status_code == 200
        assert me.json()["username"] == "alice_test"

    def test_duplicate_username_is_rejected(self, client):
        payload = {"username": "bob_test", "password": "correct-horse-battery"}
        first = client.post("/auth/register", json=payload)
        assert first.status_code == 201

        second = client.post("/auth/register", json=payload)
        assert second.status_code == 400

    def test_username_too_short_is_rejected(self, client):
        # Length is no longer enforced by this schema's own Field bounds
        # (min_length=1, deliberately loose — see RegisterRequest's own
        # comment) — it's enforced once, centrally, by
        # app/usernames.py::validate_username, called from the router.
        # That's a 400 from application code, not a 422 from Pydantic
        # field validation; the two are enforced in different layers now,
        # on purpose, so username rules can't drift out of sync between a
        # schema constraint and a router-level check the way case
        # sensitivity once did (see that module's docstring).
        resp = client.post("/auth/register", json={"username": "ab", "password": "correct-horse-battery"})
        assert resp.status_code == 400

    def test_password_too_short_is_rejected(self, client):
        resp = client.post("/auth/register", json={"username": "short_pw_test", "password": "12345"})
        assert resp.status_code == 422

    def test_blank_after_trim_username_is_rejected(self, client):
        # Same relocation as test_username_too_short_is_rejected above:
        # app/usernames.py::validate_username strips whitespace and
        # rejects the result if nothing's left — "   " is non-empty
        # before trimming (passing RegisterRequest's own loose
        # min_length=1) but blank after, caught by the router-level
        # check rather than the schema, hence 400 rather than 422.
        resp = client.post("/auth/register", json={"username": "   ", "password": "correct-horse-battery"})
        assert resp.status_code == 400

    def test_unknown_referral_code_is_ignored_not_rejected(self, client):
        # An unrecognized/typo'd code shouldn't block account creation —
        # see RegisterRequest.referral_code's own docstring.
        resp = client.post(
            "/auth/register",
            json={
                "username": "referred_test",
                "password": "correct-horse-battery",
                "referral_code": "THIS-CODE-DOES-NOT-EXIST",
            },
        )
        assert resp.status_code == 201


class TestLogin:
    def test_correct_credentials_succeed(self, client):
        client.post("/auth/register", json={"username": "carol_test", "password": "correct-horse-battery"})
        resp = client.post("/auth/login", json={"username": "carol_test", "password": "correct-horse-battery"})
        assert resp.status_code == 200
        assert resp.json()["access_token"]

    def test_wrong_password_is_rejected(self, client):
        client.post("/auth/register", json={"username": "dave_test", "password": "correct-horse-battery"})
        resp = client.post("/auth/login", json={"username": "dave_test", "password": "wrong-password"})
        assert resp.status_code == 401

    def test_unknown_username_fails_the_same_way_as_wrong_password(self, client):
        # Doesn't (can't, from black-box HTTP tests) prove the bcrypt
        # timing is identical — see auth.py's _DUMMY_PASSWORD_HASH
        # comment for that — but it does prove the two cases are at
        # least indistinguishable in status code and message, which is
        # the other half of not leaking which usernames exist.
        resp = client.post("/auth/login", json={"username": "nobody_by_this_name", "password": "whatever"})
        assert resp.status_code == 401
        assert resp.json()["detail"] == "Invalid username or password"

        client.post("/auth/register", json={"username": "eve_test", "password": "correct-horse-battery"})
        wrong_pw = client.post("/auth/login", json={"username": "eve_test", "password": "whatever"})
        assert wrong_pw.status_code == 401
        assert wrong_pw.json()["detail"] == resp.json()["detail"]


class TestMe:
    def test_requires_a_token(self, client):
        resp = client.get("/auth/me")
        assert resp.status_code == 401

    def test_rejects_a_garbage_token(self, client):
        resp = client.get("/auth/me", headers={"Authorization": "Bearer not-a-real-token"})
        assert resp.status_code == 401


class TestRateLimiting:
    def test_register_is_rate_limited_after_five_per_minute(self, client):
        # register_limiter = RateLimiter("register", max_calls=5, window_seconds=60)
        # — see app/rate_limit.py. All requests in a test come from the
        # same simulated TestClient address, so they share one bucket.
        for i in range(5):
            resp = client.post(
                "/auth/register",
                json={"username": f"ratelimit_reg_{i}", "password": "correct-horse-battery"},
            )
            assert resp.status_code == 201, f"attempt {i} should still be under the limit: {resp.text}"

        sixth = client.post(
            "/auth/register",
            json={"username": "ratelimit_reg_sixth", "password": "correct-horse-battery"},
        )
        assert sixth.status_code == 429

    def test_login_is_rate_limited_after_ten_per_minute(self, client):
        # login_limiter = RateLimiter("login", max_calls=10, window_seconds=60).
        # The limiter check runs before the password is even checked, so
        # these can all be wrong-password attempts against one account.
        client.post("/auth/register", json={"username": "ratelimit_login", "password": "correct-horse-battery"})
        for i in range(10):
            resp = client.post("/auth/login", json={"username": "ratelimit_login", "password": "wrong"})
            assert resp.status_code == 401, f"attempt {i} should still be under the limit: {resp.text}"

        eleventh = client.post("/auth/login", json={"username": "ratelimit_login", "password": "wrong"})
        assert eleventh.status_code == 429
