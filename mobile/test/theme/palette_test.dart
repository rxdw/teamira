// Unit tests for SeenlyPalette.ratingColor — the 1..10 rating gradient
// used by the diary jar tickets, the drop animation, and filled hearts.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/theme/palette.dart';

void main() {
  // ratingColor reads SeenlyPalette's ambient theme state, which in its
  // ThemeMode.system default falls through to
  // SchedulerBinding.instance.platformDispatcher — that binding isn't
  // set up automatically for a plain test() the way testWidgets() sets
  // it up for widget tests, so it's initialized explicitly here.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SeenlyPalette.ratingColor', () {
    test('null rating falls back to the neutral "not yet rated" color', () {
      expect(SeenlyPalette.ratingColor(null), SeenlyPalette.inkFaint);
    });

    test('zero and negative ratings also fall back to the neutral color',
        () {
      // 0 means "not yet rated" on this app's 1-10 heart scale — it must
      // not be treated as the bottom of the gradient (that's rating 1).
      expect(SeenlyPalette.ratingColor(0), SeenlyPalette.inkFaint);
      expect(SeenlyPalette.ratingColor(-1), SeenlyPalette.inkFaint);
    });

    test('rating 1 sits exactly at the gradient\'s first stop', () {
      expect(SeenlyPalette.ratingColor(1), SeenlyPalette.coral);
    });

    test('rating 10 sits exactly at the gradient\'s last stop', () {
      expect(SeenlyPalette.ratingColor(10), SeenlyPalette.accent);
    });

    test('every rating from 1 to 10 returns a distinct, non-neutral color',
        () {
      final colors = List.generate(10, (i) => SeenlyPalette.ratingColor(i + 1));
      expect(colors.toSet(), hasLength(10));
      for (final c in colors) {
        expect(c, isNot(SeenlyPalette.inkFaint));
      }
    });

    test('adjacent ratings interpolate rather than jump straight to a stop',
        () {
      // ratingColor blends continuously between the four named stops
      // (coral/mustard/sage/accent) rather than snapping into hard
      // buckets — see the function's own docstring on why (6/10 and
      // 7/10 should sit visibly close together). A rating strictly
      // between two stops must differ from both of its neighbors.
      final r5 = SeenlyPalette.ratingColor(5);
      final r6 = SeenlyPalette.ratingColor(6);
      expect(r5, isNot(SeenlyPalette.ratingColor(4)));
      expect(r6, isNot(r5));
    });
  });
}
