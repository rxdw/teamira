// Unit tests for analytics/screen_names.dart — the rule that turns a
// widget's class name into an analytics screen name. It must agree with
// tools/analytics/list_screens.py (which builds the list of screens the
// backend report subtracts from), so the cases here are the contract.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/analytics/screen_names.dart';

void main() {
  group('screenNameFromTypeName', () {
    test('a public screen keeps its name', () {
      final r = screenNameFromTypeName('TitleDetailScreen');
      expect(r, isNotNull);
      expect(r!.name, 'TitleDetailScreen');
      expect(r.kind, 'screen');
    });

    test('a private screen loses the leading underscore', () {
      final r = screenNameFromTypeName('_SessionsScreen');
      expect(r!.name, 'SessionsScreen');
      expect(r.kind, 'screen');
    });

    test('sheets are recognised as sheets', () {
      final r = screenNameFromTypeName('_PlanEveningSheet');
      expect(r!.name, 'PlanEveningSheet');
      expect(r.kind, 'sheet');
    });

    test('widgets that are neither are ignored', () {
      expect(screenNameFromTypeName('Scaffold'), isNull);
      expect(screenNameFromTypeName('_TabFade'), isNull);
      expect(screenNameFromTypeName('DiaryScreenState'), isNull);
      expect(screenNameFromTypeName('_CarouselPage'), isNull);
    });

    test('the bare words Screen / Sheet are not screens', () {
      expect(screenNameFromTypeName('Screen'), isNull);
      expect(screenNameFromTypeName('Sheet'), isNull);
    });

    test('Flutter\'s own bottom-sheet wrappers are never mistaken for the app\'s sheet', () {
      // These sit above the app's content inside every bottom-sheet route;
      // matching them would name every sheet "BottomSheet".
      expect(screenNameFromTypeName('BottomSheet'), isNull);
      expect(screenNameFromTypeName('_ModalBottomSheet'), isNull);
      expect(screenNameFromTypeName('DraggableScrollableSheet'), isNull);
      expect(screenNameFromTypeName('CupertinoActionSheet'), isNull);
    });

    test('generic widgets are skipped rather than half-named', () {
      expect(screenNameFromTypeName('PickerScreen<String>'), isNull);
    });
  });
}
