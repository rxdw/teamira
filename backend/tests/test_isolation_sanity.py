"""Not a test of the app — a test of the test suite's own isolation.

conftest.py's `db_session` fixture is supposed to roll back everything
a test did, including rows committed mid-request by route code (see
that fixture's docstring for how). These two tests exist to prove that
in the most direct way possible: if isolation ever quietly breaks —
someone "simplifies" `db_session` and drops the SAVEPOINT dance, say —
this fails immediately and points straight at the fixture, instead of
turning into a confusing, order-dependent failure in some unrelated
test three files away that happens to reuse a username.

Order matters here (pytest runs a file's tests top-to-bottom by
default): if these ran in the other order, or in isolation, the second
test alone wouldn't prove anything.
"""


def test_1_register_a_fixed_username(client):
    resp = client.post(
        "/auth/register",
        json={"username": "isolation_check_user", "password": "correct-horse-battery"},
    )
    assert resp.status_code == 201


def test_2_that_same_username_is_available_again(client):
    # Only possible if test_1's insert was rolled back at teardown
    # rather than actually committed to the database.
    resp = client.post(
        "/auth/register",
        json={"username": "isolation_check_user", "password": "correct-horse-battery"},
    )
    assert resp.status_code == 201, (
        "got a duplicate-username error, which means the previous test's data "
        "survived — db_session's rollback-per-test isolation is broken"
    )
