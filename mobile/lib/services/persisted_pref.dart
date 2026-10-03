import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One [SharedPreferences]-backed value, with the get-or-default + set +
/// notify boilerplate written once instead of hand-copied into every
/// `*_prefs_service.dart` file.
///
/// Fixes the two problems that boilerplate had in practice:
/// - Multiple independent, slightly different copies of the same
///   load/save shape, one per prefs service.
/// - No single settled order between updating the in-memory value,
///   calling [notifyListeners], and awaiting the write to disk — some
///   files did it one way, some the other. This class always does it in
///   the same order: update the value, notify listeners, *then* await
///   the write — so a rebuild triggered by [notifyListeners] never has
///   to wait on disk I/O first, matching the pattern most of the
///   hand-written services already agreed on informally.
///
/// A `*PrefsService` class holds one `PersistedPref<T>` field per stored
/// value (see e.g. SpoilerPrefsService, ThemePrefsService) and forwards
/// its own `load()`/setter methods to the fields' [load]/[save] — the
/// public API each screen already calls doesn't change.
///
/// Not a fit for every prefs service as-is: one whose key is
/// parameterized per call (e.g. SeriesRoutePrefsService, one blob per
/// media id) or that carries its own migration/account-scoping logic
/// (e.g. OnThisDayPrefsService, TodayPickPrefsService) needs that logic
/// to stay explicit rather than being forced through a single fixed-key
/// wrapper.
class PersistedPref<T> extends ChangeNotifier {
  PersistedPref(
    this.key, {
    required this.defaultValue,
    required T Function(SharedPreferences prefs, String key) read,
    required Future<void> Function(SharedPreferences prefs, String key, T value) write,
    // Defaults to plain `==`, which is exactly right for bool/String/int
    // (and their nullable counterparts) since those compare by value
    // already. Only a T whose `==` is identity-based — a bare Dart
    // Set/List/Map, which none of dart:core's collections override —
    // needs a real comparator passed in here (see [stringSet] below),
    // or the "skip redundant writes" guard in [save] silently never
    // fires for it.
    bool Function(T a, T b)? equals,
  })  : _read = read,
        _write = write,
        _equals = equals ?? ((a, b) => a == b),
        _value = defaultValue;

  final String key;
  final T defaultValue;
  final T Function(SharedPreferences prefs, String key) _read;
  final Future<void> Function(SharedPreferences prefs, String key, T value) _write;
  final bool Function(T a, T b) _equals;

  T _value;
  T get value => _value;

  /// Re-reads [key] from disk into [value] and notifies listeners.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _value = _read(prefs, key);
    notifyListeners();
  }

  /// Updates [value] in memory, notifies listeners, then persists it.
  /// A no-op if [value] is unchanged — same "skip redundant writes"
  /// guard every hand-written setter had.
  ///
  /// [onChanged] fires synchronously in that same spot — after the
  /// in-memory update, before the disk write is awaited. A wrapping
  /// `*PrefsService` that composes several `PersistedPref` fields (see
  /// ThemePrefsService, SpoilerPrefsService) passes its own
  /// `notifyListeners` here so *its* listeners get the same
  /// notify-before-write ordering as this field's own listeners do —
  /// awaiting [save] fully before calling the outer `notifyListeners`
  /// would push that notification behind the disk write instead.
  Future<void> save(T value, {VoidCallback? onChanged}) async {
    if (_equals(_value, value)) return;
    _value = value;
    notifyListeners();
    onChanged?.call();
    final prefs = await SharedPreferences.getInstance();
    await _write(prefs, key, value);
  }

  // ---------------------------------------------------------------------
  // Convenience constructors for the common shapes. Anything more
  // specific (enums, JSON blobs, compound values) can still use the
  // main constructor directly with a custom read/write pair.
  // ---------------------------------------------------------------------

  static PersistedPref<bool> boolean(String key, {bool defaultValue = false}) {
    return PersistedPref<bool>(
      key,
      defaultValue: defaultValue,
      read: (prefs, k) => prefs.getBool(k) ?? defaultValue,
      write: (prefs, k, v) => prefs.setBool(k, v),
    );
  }

  static PersistedPref<String> string(String key, {String defaultValue = ''}) {
    return PersistedPref<String>(
      key,
      defaultValue: defaultValue,
      read: (prefs, k) => prefs.getString(k) ?? defaultValue,
      write: (prefs, k, v) => prefs.setString(k, v),
    );
  }

  /// An int that's absent (rather than defaulted) when unset — writes
  /// `null` by removing the key instead of storing a sentinel.
  static PersistedPref<int?> nullableInt(String key) {
    return PersistedPref<int?>(
      key,
      defaultValue: null,
      read: (prefs, k) => prefs.getInt(k),
      write: (prefs, k, v) async {
        if (v == null) {
          await prefs.remove(k);
        } else {
          await prefs.setInt(k, v);
        }
      },
    );
  }

  /// A string that's absent (rather than defaulted) when unset — writes
  /// `null` by removing the key instead of storing a sentinel. The
  /// nullable counterpart to [nullableInt].
  static PersistedPref<String?> nullableString(String key) {
    return PersistedPref<String?>(
      key,
      defaultValue: null,
      read: (prefs, k) => prefs.getString(k),
      write: (prefs, k, v) async {
        if (v == null) {
          await prefs.remove(k);
        } else {
          await prefs.setString(k, v);
        }
      },
    );
  }

  /// Backed by [SharedPreferences.getStringList]/setStringList, exposed
  /// as a [Set] — the shape every "which types/genres are picked" prefs
  /// value in this app actually wants.
  static PersistedPref<Set<String>> stringSet(String key) {
    return PersistedPref<Set<String>>(
      key,
      defaultValue: const <String>{},
      read: (prefs, k) => (prefs.getStringList(k) ?? const []).toSet(),
      write: (prefs, k, v) => prefs.setStringList(k, v.toList()),
      // Set has no value equality of its own (same as List/Map — see
      // this constructor's own comment on [equals]), so without this,
      // save()'s "skip redundant writes" guard would compare two
      // same-contents-but-different-instance Sets as unequal and
      // re-notify/re-write on every single call, genre picker toggle or
      // not.
      equals: const SetEquality<String>().equals,
    );
  }
}
