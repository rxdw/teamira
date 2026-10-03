// Unit tests for utils/server_time.dart.
//
// Context: the backend hands back naive "2026-08-13T20:45:00"-style
// timestamps for every server-generated `created_at` (and the
// co-viewing poll's `deadline`) — no 'Z', no offset, but it's really
// always an instant in UTC (server_default=func.now() / datetime.
// utcnow()). Dart's own DateTime.parse treats a timestamp with no
// timezone marker as already *local*, so parsing one of these directly
// silently shows the wrong clock time — and the wrong "x minutes ago"
// — to anyone not physically in UTC. parseServerUtc/tryParseServerUtc
// fix that by forcing the 'Z' before parsing.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/utils/server_time.dart';

void main() {
  group('parseServerUtc', () {
    test('a naive timestamp with no zone marker is read as UTC, not local', () {
      final result = parseServerUtc('2026-08-13T20:45:00');
      expect(result.isUtc, isTrue);
      expect(result.hour, 20);
      expect(result.minute, 45);
    });

    test('a timestamp that already ends in Z is left as-is, not double-suffixed', () {
      final result = parseServerUtc('2026-08-13T20:45:00Z');
      expect(result.isUtc, isTrue);
      expect(result.hour, 20);
    });

    test('a timestamp with an explicit offset is left as-is', () {
      final result = parseServerUtc('2026-08-13T20:45:00+03:00');
      // 20:45 at +03:00 is 17:45 UTC.
      expect(result.toUtc().hour, 17);
    });

    test('microseconds in a naive timestamp still parse correctly', () {
      final result = parseServerUtc('2026-08-13T20:45:00.123456');
      expect(result.isUtc, isTrue);
      expect(result.microsecond, 456);
    });

    // The actual regression this exists for: two people in different
    // timezones reading the same server instant must compute the same
    // "how long ago" duration, and it must be roughly zero for a
    // timestamp that was just generated.
    test('a freshly-minted UTC-now timestamp reads as "just happened", not offset by the local zone', () {
      final nowUtcNaive = DateTime.now().toUtc();
      // Simulate exactly what the backend sends: no 'Z', naive-looking.
      final iso = nowUtcNaive.toIso8601String().replaceAll('Z', '');
      final parsed = parseServerUtc(iso);
      final diff = DateTime.now().toUtc().difference(parsed).abs();
      expect(diff.inSeconds, lessThan(5));
    });
  });

  group('tryParseServerUtc', () {
    test('returns null for a null input instead of throwing', () {
      expect(tryParseServerUtc(null), isNull);
    });

    test('returns null for an empty string instead of throwing', () {
      expect(tryParseServerUtc(''), isNull);
    });

    test('returns null for garbage input instead of throwing', () {
      expect(tryParseServerUtc('not a date'), isNull);
    });

    test('parses a valid naive timestamp the same way parseServerUtc does', () {
      final result = tryParseServerUtc('2026-01-01T00:00:00');
      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.month, 1);
      expect(result.day, 1);
    });
  });
}
