// The onboarding funnel is reported by *step number*; the backend's
// analytics report turns numbers back into names with its own list. Nothing
// ties the two lists to each other except this test, so when someone inserts
// a step (as the "partner" step was) and forgets the other side, it fails
// here rather than leaving a silently mislabelled funnel.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<String> _quotedNames(String listBody) =>
    RegExp(r"""['"]([a-z_]+)['"]""").allMatches(listBody).map((m) => m.group(1)!).toList();

void main() {
  final screen = File('lib/screens/onboarding/onboarding_screen.dart');
  final report = File('../backend/scripts/analytics_report.py');

  late final List<String> appSteps;
  late final int pageCount;

  setUpAll(() {
    final src = screen.readAsStringSync();
    final names = RegExp(r'static const _stepNames = \[(.*?)\];', dotAll: true).firstMatch(src);
    expect(names, isNotNull, reason: '_stepNames not found in onboarding_screen.dart');
    appSteps = _quotedNames(names!.group(1)!);
    final count = RegExp(r'static const _pageCount = (\d+);').firstMatch(src);
    expect(count, isNotNull, reason: '_pageCount not found in onboarding_screen.dart');
    pageCount = int.parse(count!.group(1)!);
  });

  test('every step has a name, and the page count agrees with the names', () {
    expect(appSteps.toSet().length, appSteps.length, reason: 'duplicate step names');
    expect(appSteps.length, pageCount);
  });

  test('connecting a partner is part of the flow, right after the tour', () {
    expect(appSteps, contains('partner'));
    expect(appSteps.indexOf('partner'), appSteps.indexOf('features_tour') + 1);
  });

  test('the two steps the confetti is keyed to still exist (they are looked up by name)', () {
    expect(appSteps, containsAll(['favorites', 'people_like_you']));
  });

  test('the backend funnel names the same steps in the same order', () {
    if (!report.existsSync()) {
      markTestSkipped('backend/scripts/analytics_report.py is not next to mobile/ here');
      return;
    }
    final match = RegExp(r'ONBOARDING_STEPS = \[(.*?)\]', dotAll: true).firstMatch(report.readAsStringSync());
    expect(match, isNotNull, reason: 'ONBOARDING_STEPS not found in analytics_report.py');
    expect(_quotedNames(match!.group(1)!), appSteps);
  });
}
