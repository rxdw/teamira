import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A tiny on-device cache for repository classes (see
/// `repositories/diary_repository.dart`, `repositories/watchlist_repository.dart`)
/// to keep a copy of the signed-in account's own data between app
/// launches and while offline — see Фаза 2.15 in the launch plan for why
/// this exists alongside the server's Postgres database rather than
/// instead of it: this only ever holds this one device's copy of this
/// one user's data, never a second source of truth.
///
/// Deliberately just JSON files under the app's documents directory,
/// not `drift`/`isar`/`sqflite` — see 2.15.1's own reasoning. A
/// repository is the only thing that should ever touch this directly;
/// screens go through the relevant `*Store` instead.
class LocalJsonCache {
  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _file(String key) async {
    final dir = await _dir();
    return File('${dir.path}/$key.json');
  }

  /// Returns the decoded JSON previously written under [key], or `null`
  /// if there's nothing cached yet, the file is unreadable, or it no
  /// longer matches the shape the caller expects — a missing/corrupt
  /// cache is never a fatal error, only a cache miss.
  Future<dynamic> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Best-effort write — a failed cache write should never take down
  /// whatever action triggered it (see callers in the repositories).
  Future<void> write(String key, dynamic value) async {
    try {
      final file = await _file(key);
      await file.writeAsString(jsonEncode(value));
    } catch (_) {
      // Ignored on purpose — see the doc comment above.
    }
  }

  Future<void> delete(String key) async {
    try {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ignored on purpose — see the doc comment above.
    }
  }
}
