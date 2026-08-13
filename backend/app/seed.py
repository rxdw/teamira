"""
Seeds `affiliate_providers` with a starting `deep_link_template` for the
handful of providers people actually run into most — each one today just a
plain, non-affiliate search URL for that provider (so a tap always opens
somewhere real), keyed by TMDB's provider_id. This only INSERTs rows that
don't exist yet; it never overwrites a template you've since edited (by
hand or once a real affiliate deal is in place), so re-running it on every
deploy is always safe.

Provider IDs are TMDB's own (https://api.themoviedb.org/3/watch/providers/
movie lists all of them with names) — the ones below are the common US/UK
catalog; add more rows the same way as new providers matter to your
audience. See app/routers/watch.py for the full monetization picture, and
app/models.py::AffiliateProvider for what changes when a real deal lands.
"""

from sqlalchemy.orm import Session

from app import models

# provider_key (TMDB provider_id) -> (display name, non-affiliate search URL template)
_SEED_PROVIDERS: dict[str, tuple[str, str]] = {
    "8": ("Netflix", "https://www.netflix.com/search?q={title}"),
    "337": ("Disney Plus", "https://www.disneyplus.com/search/{title}"),
    "9": ("Amazon Prime Video", "https://www.amazon.com/s?k={title}&i=instant-video"),
    "119": ("Amazon Prime Video", "https://www.amazon.com/s?k={title}&i=instant-video"),
    "350": ("Apple TV", "https://tv.apple.com/search/{title}"),
    "1899": ("Max", "https://www.max.com/search?q={title}"),
    "384": ("Max", "https://www.max.com/search?q={title}"),
    "15": ("Hulu", "https://www.hulu.com/search?q={title}"),
    "531": ("Paramount Plus", "https://www.paramountplus.com/search/{title}/"),
    "386": ("Peacock", "https://www.peacocktv.com/search?q={title}"),
    "283": ("Crunchyroll", "https://www.crunchyroll.com/search?q={title}"),
}


def seed_affiliate_providers(db: Session) -> None:
    changed = False
    for provider_key, (display_name, template) in _SEED_PROVIDERS.items():
        if db.get(models.AffiliateProvider, provider_key) is not None:
            continue
        db.add(models.AffiliateProvider(
            provider_key=provider_key,
            display_name=display_name,
            deep_link_template=template,
            is_affiliate=0,
        ))
        changed = True
    if changed:
        db.commit()
