// Unit tests for services/referral_link_service.dart's extractFromUri —
// the only pure, no-IO piece of the referral flow (the other three
// entry points touch SharedPreferences, the clipboard, or the Android
// Play Install Referrer API, which need platform mocking to exercise
// meaningfully). extractFromUri is a plain Uri -> String? function and
// is exactly the kind of "looks obviously right" string/path logic
// that's worth covering directly.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/services/referral_link_service.dart';

void main() {
  group('ReferralLinkService.extractFromUri — query param form', () {
    test('extracts the code from a custom-scheme link', () {
      final uri = Uri.parse('seenly://invite?code=ABC123');
      expect(ReferralLinkService.extractFromUri(uri), 'ABC123');
    });

    test('query param wins even when the path also looks like /i/<code>', () {
      final uri = Uri.parse('https://seenly.app/i/PATHCODE?code=QUERYCODE');
      expect(ReferralLinkService.extractFromUri(uri), 'QUERYCODE');
    });

    test('an empty ?code= is treated as absent, not as an empty code', () {
      final uri = Uri.parse('seenly://invite?code=');
      expect(ReferralLinkService.extractFromUri(uri), isNull);
    });
  });

  group('ReferralLinkService.extractFromUri — https App Link /i/<code> form', () {
    test('extracts the code from a plain /i/<code> path', () {
      final uri = Uri.parse('https://seenly.app/i/XYZ789');
      expect(ReferralLinkService.extractFromUri(uri), 'XYZ789');
    });

    // Regression test: a trailing slash used to leave an empty string as
    // the last path segment ('i', 'XYZ789', ''), which shifted 'i' out
    // of the length-2-from-the-end position this check looks at — the
    // code was silently never extracted even though it's plainly there
    // in the URL.
    test('still extracts the code when the link has a trailing slash', () {
      final uri = Uri.parse('https://seenly.app/i/XYZ789/');
      expect(ReferralLinkService.extractFromUri(uri), 'XYZ789');
    });

    test('handles a nested/prefixed path as long as ".../i/<code>" is the tail', () {
      final uri = Uri.parse('https://seenly.app/app/i/XYZ789');
      expect(ReferralLinkService.extractFromUri(uri), 'XYZ789');
    });

    test('returns null when there is no "i" segment at all', () {
      final uri = Uri.parse('https://seenly.app/XYZ789');
      expect(ReferralLinkService.extractFromUri(uri), isNull);
    });

    test('returns null for a bare "i" with nothing after it', () {
      final uri = Uri.parse('https://seenly.app/i');
      expect(ReferralLinkService.extractFromUri(uri), isNull);
    });

    test('returns null when the last segment is empty (trailing slash, no code)', () {
      final uri = Uri.parse('https://seenly.app/i/');
      expect(ReferralLinkService.extractFromUri(uri), isNull);
    });

    test('is case-sensitive about the "i" marker segment', () {
      final uri = Uri.parse('https://seenly.app/I/XYZ789');
      expect(ReferralLinkService.extractFromUri(uri), isNull);
    });
  });

  group('ReferralLinkService.extractFromUri — no code present', () {
    test('a totally unrelated URL returns null', () {
      final uri = Uri.parse('https://seenly.app/about');
      expect(ReferralLinkService.extractFromUri(uri), isNull);
    });

    test('the app scheme with no query at all returns null', () {
      final uri = Uri.parse('seenly://invite');
      expect(ReferralLinkService.extractFromUri(uri), isNull);
    });
  });
}
