// Widget tests for widgets/heart_rating.dart — the 1-10 heart control
// used everywhere a rating is shown or picked (Diary rows, the log
// flow, the edit-review sheet, series episodes).
//
// This is the one widget test in the suite for now: HeartRating is
// self-contained (no Provider/network/SharedPreferences dependency,
// unlike almost every screen — see app.dart's SeenlyApp, which needs 15
// pre-loaded services plus a real network call just to boot), so it's
// the highest-value, lowest-risk widget to pump directly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/widgets/heart_rating.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('HeartRating rendering', () {
    testWidgets('renders exactly `max` hearts', (tester) async {
      await tester.pumpWidget(_wrap(const HeartRating(value: 3, max: 10)));
      await tester.pump();

      final filled = find.byIcon(Icons.favorite);
      final empty = find.byIcon(Icons.favorite_border);
      expect(tester.widgetList(filled).length + tester.widgetList(empty).length, 10);
    });

    testWidgets('fills exactly `value` hearts, the rest stay outlined',
        (tester) async {
      await tester.pumpWidget(_wrap(const HeartRating(value: 4, max: 10)));
      await tester.pump();

      expect(find.byIcon(Icons.favorite), findsNWidgets(4));
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(6));
    });

    testWidgets('value 0 renders every heart outlined', (tester) async {
      await tester.pumpWidget(_wrap(const HeartRating(value: 0, max: 10)));
      await tester.pump();

      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(10));
    });

    testWidgets('respects a smaller max (e.g. a 1-5 legacy row)',
        (tester) async {
      await tester.pumpWidget(_wrap(const HeartRating(value: 2, max: 5)));
      await tester.pump();

      expect(find.byIcon(Icons.favorite), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(3));
    });
  });

  group('HeartRating interaction', () {
    testWidgets('tapping the Nth heart reports N through onChanged',
        (tester) async {
      int? reported;
      await tester.pumpWidget(_wrap(HeartRating(
        value: 2,
        max: 10,
        onChanged: (v) => reported = v,
      )));
      await tester.pump();

      // Tap the 7th heart (index 6 among the 10 GestureDetectors) —
      // scoped to descendants of HeartRating itself, since MaterialApp/
      // Scaffold add their own GestureDetectors elsewhere in the tree.
      final hearts = find.descendant(
        of: find.byType(HeartRating),
        matching: find.byType(GestureDetector),
      );
      expect(hearts, findsNWidgets(10));
      await tester.tap(hearts.at(6));
      await tester.pump();

      expect(reported, 7);
    });

    testWidgets('is read-only (does not throw, no report) when onChanged is null',
        (tester) async {
      await tester.pumpWidget(_wrap(const HeartRating(value: 5, max: 10)));
      await tester.pump();

      // Must not throw even though there's nothing listening — a null
      // onChanged means every GestureDetector's onTap is itself null.
      final hearts = find.descendant(
        of: find.byType(HeartRating),
        matching: find.byType(GestureDetector),
      );
      await tester.tap(hearts.at(0));
      await tester.pump();

      // Read-only rows (Diary, watched-preview, series episodes) rely on
      // the displayed value staying exactly what was passed in.
      expect(find.byIcon(Icons.favorite), findsNWidgets(5));
    });
  });
}
