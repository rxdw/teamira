/// The backend hands back naive `"2026-08-13T20:45:00"`-style strings
/// for every server-generated timestamp (`created_at` on pretty much
/// every model — see backend/app/models.py's `Column(DateTime,
/// server_default=func.now())` fields, and the co-viewing poll's
/// `deadline`, built from `datetime.utcnow()`). Every one of them is
/// really an instant in UTC, but carries no 'Z'/offset to say so.
///
/// Dart's own `DateTime.parse`/`tryParse` treats a timestamp with no
/// timezone marker as already local — so parsing one of these directly
/// silently shows the wrong clock time (and the wrong "x minutes/hours
/// ago") to anyone not physically in UTC. Forcing the 'Z' here first
/// makes it parse as the UTC instant it actually is; call `.toLocal()`
/// on the result wherever a local wall-clock time should be displayed.
///
/// Does NOT apply to timestamps that came from somewhere else and
/// already carry their own offset — e.g. TMDB's own `created_at` on
/// review data (see models/tmdb_review.dart), which TMDB already
/// returns with a 'Z'. Only use this for our own backend's timestamps.
library;

DateTime parseServerUtc(String iso) =>
    DateTime.parse(iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z');

/// Same as [parseServerUtc], but returns null instead of throwing on a
/// missing/malformed string — for the many optional `created_at`-style
/// fields that are only sometimes present.
DateTime? tryParseServerUtc(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final withZone = iso.endsWith('Z') || iso.contains('+') ? iso : '${iso}Z';
  return DateTime.tryParse(withZone);
}
