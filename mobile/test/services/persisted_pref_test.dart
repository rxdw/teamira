// Unit tests for services/persisted_pref.dart — the shared
// SharedPreferences wrapper every `*PrefsService` in the app (theme,
// spoilers, ritual, auto-tracking, etc.) is built on top of. A bug here
// is a bug in all of them at once, which is exactly why it's worth
// covering directly rather than only indirectly through whichever
// PrefsService happens to have its own tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamira/services/persisted_pref.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PersistedPref.boolean', () {
    test('load() reads the default when nothing was ever saved', () async {
      SharedPreferences.setMockInitialValues({});
      final pref = PersistedPref.boolean('flag', defaultValue: true);
      await pref.load();
      expect(pref.value, isTrue);
    });

    test('load() reads back a previously-saved value', () async {
      SharedPreferences.setMockInitialValues({'flag': true});
      final pref = PersistedPref.boolean('flag');
      await pref.load();
      expect(pref.value, isTrue);
    });

    test('save() updates the in-memory value immediately', () async {
      SharedPreferences.setMockInitialValues({});
      final pref = PersistedPref.boolean('flag');
      await pref.save(true);
      expect(pref.value, isTrue);
    });

    test('save() persists to disk — a fresh instance reading the same key sees it',
        () async {
      SharedPreferences.setMockInitialValues({});
      final writer = PersistedPref.boolean('flag');
      await writer.save(true);

      final reader = PersistedPref.boolean('flag');
      await reader.load();
      expect(reader.value, isTrue);
    });

    test('save() notifies listeners exactly once per actual change', () async {
      SharedPreferences.setMockInitialValues({});
      final pref = PersistedPref.boolean('flag');
      var notifications = 0;
      pref.addListener(() => notifications++);

      await pref.save(true);
      expect(notifications, 1);
    });

    test('save() is a no-op (no notify, no write) when the value is unchanged',
        () async {
      // Documented in persisted_pref.dart's own doc comment: "A no-op if
      // value is unchanged — same skip-redundant-writes guard every
      // hand-written setter had."
      SharedPreferences.setMockInitialValues({});
      final pref = PersistedPref.boolean('flag', defaultValue: false);
      var notifications = 0;
      pref.addListener(() => notifications++);

      await pref.save(false); // already false — should be a no-op
      expect(notifications, 0);
    });

    test('save() calls onChanged synchronously alongside its own listeners',
        () async {
      SharedPreferences.setMockInitialValues({});
      final pref = PersistedPref.boolean('flag');
      var onChangedCalled = false;

      await pref.save(true, onChanged: () => onChangedCalled = true);
      expect(onChangedCalled, isTrue);
    });
  });

  group('PersistedPref.nullableInt / nullableString', () {
    test('default to null when unset', () async {
      SharedPreferences.setMockInitialValues({});
      final intPref = PersistedPref.nullableInt('watch_region_id');
      final stringPref = PersistedPref.nullableString('watch_region');
      await intPref.load();
      await stringPref.load();
      expect(intPref.value, isNull);
      expect(stringPref.value, isNull);
    });

    test('saving null removes the underlying key instead of storing a sentinel',
        () async {
      SharedPreferences.setMockInitialValues({'watch_region': 'RU'});
      final pref = PersistedPref.nullableString('watch_region');
      await pref.load();
      expect(pref.value, 'RU');

      await pref.save(null);
      expect(pref.value, isNull);

      // A fresh instance reading the same key must also see it gone, not
      // find some leftover sentinel value.
      final reader = PersistedPref.nullableString('watch_region');
      await reader.load();
      expect(reader.value, isNull);
    });
  });

  group('PersistedPref.stringSet', () {
    test('load() reads a saved string list back as a Set', () async {
      SharedPreferences.setMockInitialValues({
        'genres': ['Action', 'RPG'],
      });
      final pref = PersistedPref.stringSet('genres');
      await pref.load();
      expect(pref.value, {'Action', 'RPG'});
    });

    test('defaults to an empty set when unset', () async {
      SharedPreferences.setMockInitialValues({});
      final pref = PersistedPref.stringSet('genres');
      await pref.load();
      expect(pref.value, isEmpty);
    });

    test(
        'save() is a no-op for stringSet when the new Set has the same '
        'contents, even as a different Set instance', () async {
      // PersistedPref's own doc comment promises save() is "a no-op if
      // value is unchanged". A plain `_value == value` can't deliver
      // that for Set (Set has no value equality of its own — same as
      // List/Map), so stringSet passes SetEquality<String>().equals as
      // its comparator (see persisted_pref.dart's own comment on the
      // constructor's `equals` parameter and on stringSet itself).
      SharedPreferences.setMockInitialValues({});
      final pref = PersistedPref.stringSet('genres');
      await pref.save({'Action', 'RPG'});

      var notifications = 0;
      pref.addListener(() => notifications++);
      // A different Set instance, but the exact same contents.
      await pref.save({'Action', 'RPG'});

      expect(notifications, 0);
    });

    test('save() still notifies when stringSet contents actually change',
        () async {
      SharedPreferences.setMockInitialValues({});
      final pref = PersistedPref.stringSet('genres');
      await pref.save({'Action', 'RPG'});

      var notifications = 0;
      pref.addListener(() => notifications++);
      await pref.save({'Action', 'RPG', 'Comedy'});

      expect(notifications, 1);
      expect(pref.value, {'Action', 'RPG', 'Comedy'});
    });
  });
}
