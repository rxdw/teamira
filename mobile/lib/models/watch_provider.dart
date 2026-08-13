/// Mirrors `WatchProviderOut` in backend/app/schemas.py. `outUrl` always
/// points at our own backend (`/media/watch-out`), never straight at the
/// provider — see backend/app/routers/watch.py for why (that's the one
/// place a real affiliate link gets swapped in later, without an app
/// update).
class WatchProvider {
  final String providerKey;
  final String name;
  final String? logoUrl;
  final String kind; // "flatrate" | "rent" | "buy"
  final String outUrl;

  const WatchProvider({
    required this.providerKey,
    required this.name,
    this.logoUrl,
    required this.kind,
    required this.outUrl,
  });

  factory WatchProvider.fromJson(Map<String, dynamic> json) => WatchProvider(
        providerKey: json['provider_key'] as String,
        name: json['name'] as String,
        logoUrl: json['logo_url'] as String?,
        kind: json['kind'] as String,
        outUrl: json['out_url'] as String,
      );
}

/// Mirrors `WatchProvidersOut` — an empty `providers` list just means
/// "nothing to show" (a game/book, or a title with no known streaming
/// availability), not an error.
class WatchProvidersResult {
  final String country;
  final List<WatchProvider> providers;
  final String? moreUrl;
  final String attribution;

  const WatchProvidersResult({
    required this.country,
    required this.providers,
    this.moreUrl,
    this.attribution = 'Streaming data provided by JustWatch',
  });

  factory WatchProvidersResult.fromJson(Map<String, dynamic> json) => WatchProvidersResult(
        country: json['country'] as String,
        providers: (json['providers'] as List)
            .map((e) => WatchProvider.fromJson(e as Map<String, dynamic>))
            .toList(),
        moreUrl: json['more_url'] as String?,
        attribution: json['attribution'] as String? ?? 'Streaming data provided by JustWatch',
      );
}
