"""One-off diagnostic — run inside the api container:
    docker compose exec api python3 diag.py
Delete this file once you're done; it's not part of the app.
"""
import httpx

from app.config import settings

print("=== settings loaded by the running process ===")
print("TMDB_API_KEY:      ", (settings.tmdb_api_key[:6] + "...") if settings.tmdb_api_key else "(EMPTY)")
print("IGDB_CLIENT_ID:     ", (settings.igdb_client_id[:6] + "...") if settings.igdb_client_id else "(EMPTY)")
print("IGDB_CLIENT_SECRET: ", "set" if settings.igdb_client_secret else "(EMPTY)")
print()

print("--- 1) local /media/search — what does the API actually return? ---")
try:
    r = httpx.get("http://localhost:8000/media/search", params={"q": "batman"}, timeout=10)
    data = r.json()
    print("status:", r.status_code, "| results:", len(data))
    if data:
        print("first item poster_url:", data[0].get("poster_url"))
        print("first item media_type/source:", data[0].get("media_type"), data[0].get("source"))
except Exception as e:
    print("FAILED:", repr(e))
print()

print("--- 2) api.themoviedb.org (data) ---")
try:
    r = httpx.get(
        "https://api.themoviedb.org/3/movie/550",
        params={"api_key": settings.tmdb_api_key},
        timeout=10,
    )
    print("status:", r.status_code, "| body:", r.text[:150])
except Exception as e:
    print("FAILED:", repr(e))
print()

print("--- 3) image.tmdb.org (the actual poster CDN — different domain!) ---")
try:
    r = httpx.get(
        "https://image.tmdb.org/t/p/w500/qJ2tW6WMUDux911r6m7haRef0WH.jpg", timeout=10
    )
    print("status:", r.status_code, "| content-type:", r.headers.get("content-type"), "| bytes:", len(r.content))
except Exception as e:
    print("FAILED:", repr(e))
print()

print("--- 4) IGDB / Twitch oauth ---")
try:
    r = httpx.post(
        "https://id.twitch.tv/oauth2/token",
        data={
            "client_id": settings.igdb_client_id,
            "client_secret": settings.igdb_client_secret,
            "grant_type": "client_credentials",
        },
        timeout=10,
    )
    print("status:", r.status_code, "| body:", r.text[:200])
except Exception as e:
    print("FAILED:", repr(e))
print()

print("--- 5) Open Library (no key needed) ---")
try:
    r = httpx.get(
        "https://openlibrary.org/search.json", params={"q": "naruto", "limit": 1}, timeout=10
    )
    print("status:", r.status_code, "| body:", r.text[:200])
except Exception as e:
    print("FAILED:", repr(e))
