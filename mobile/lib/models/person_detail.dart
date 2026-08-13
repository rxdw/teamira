import 'media_item.dart';

/// Mirrors `PersonDetailOut` — the response of GET /media/person, opened
/// from a tapped cast tile or "directed by ___" name (see
/// CastMember.personId / MediaItem.directorId). TMDB-only; no ratings or
/// similar-titles concept the way a title has.
class PersonDetail {
  final String personId;
  final String name;
  final String? photoUrl;
  final LocalizedText? biography;
  final String? birthday;
  final String? knownForDepartment;
  final List<MediaItem> filmography;
  // Required attribution text whenever this data is shown — same
  // reasoning as MediaDetail.tmdbAttribution.
  final String? tmdbAttribution;

  const PersonDetail({
    required this.personId,
    required this.name,
    this.photoUrl,
    this.biography,
    this.birthday,
    this.knownForDepartment,
    this.filmography = const [],
    this.tmdbAttribution,
  });

  factory PersonDetail.fromJson(Map<String, dynamic> json) => PersonDetail(
        personId: json['person_id'] as String,
        name: json['name'] as String,
        photoUrl: json['photo_url'] as String?,
        biography: json['biography'] == null
            ? null
            : LocalizedText.fromJson(json['biography'] as Map<String, dynamic>),
        birthday: json['birthday'] as String?,
        knownForDepartment: json['known_for_department'] as String?,
        filmography: (json['filmography'] as List? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        tmdbAttribution: json['tmdb_attribution'] as String?,
      );
}
