import '../models/import_row.dart';
import '../models/watchlist_entry.dart';
import 'api_client.dart';

/// "Your sources" — link-based YouTube/Twitch import, kept on its own
/// screen (separate from Settings > Import) so it doesn't mix into the
/// main movie/show shelves. See backend/app/routers/sources.py.
///
/// Reuses ImportService's commit()/[ImportRow] shapes on purpose — a
/// resolved YouTube/Twitch link *is* an import row, just one whose
/// "match" was never in question (the video itself, not a catalog
/// lookup). See ImportService for the actual commit call.
class SourcesService {
  final ApiClient _client;
  SourcesService(this._client);

  /// Resolves a pasted YouTube/Twitch URL — a single video, or every
  /// video in a playlist/channel/VOD-archive — without writing anything
  /// yet. [defaultStatus] is local bookkeeping for the returned rows,
  /// same as ImportService.preview.
  Future<ImportPreviewResult> preview(String url, {required String defaultStatus}) async {
    final json = await _client.post(
      '/import/sources/preview',
      body: {'url': url},
      timeout: const Duration(seconds: 30),
    ) as Map<String, dynamic>;
    final rows = (json['rows'] as List)
        .map((e) => ImportRow.fromJson(e as Map<String, dynamic>, defaultStatus: defaultStatus))
        .toList();
    return ImportPreviewResult(rows: rows, sourceDetected: json['source_detected'] as String);
  }

  /// The watched / watching / plan-to-watch shelves for this screen only
  /// — every WatchlistEntry whose source is "youtube" or "twitch". Same
  /// shape as ProfileService.collections(), scoped server-side.
  Future<ProfileCollections> collections() async {
    final json = await _client.get('/import/sources/collections') as Map<String, dynamic>;
    return ProfileCollections.fromJson(json);
  }
}
