import 'dart:convert';
import 'package:http/http.dart' as http;
import 'artwork_store.dart';

/// A single candidate match returned by an online metadata lookup, for the
/// user to review and pick from before it overwrites anything.
class MetadataMatch {
  final String title;
  final String artist;
  final String album;
  final int? releaseYear;
  final String? genre;
  final Duration? duration;

  /// MusicBrainz release MBID, used to fetch cover art from the Cover Art
  /// Archive. Null if this match couldn't be tied to a specific release.
  final String? releaseId;

  /// MusicBrainz's own relevance score for this match, 0-100 — how well it
  /// thinks this recording fits the search query. Used to rank candidates
  /// and shown to the user as a "% match" so they're not just guessing
  /// between several similarly-named entries.
  final int score;

  const MetadataMatch({
    required this.title,
    required this.artist,
    required this.album,
    this.releaseYear,
    this.genre,
    this.duration,
    this.releaseId,
    this.score = 0,
  });
}

/// Looks up song metadata (title/artist/album/year/genre/cover art) from
/// MusicBrainz + the Cover Art Archive — both free, keyless public APIs —
/// used to "autofill" a track's metadata when tags are missing or wrong
/// (e.g. a renamed/ripped file). Both ask that requests identify the app via
/// User-Agent, same as the Radio Browser integration.
class MetadataLookupService {
  static const _userAgent = 'Playah/1.0 (Flutter local music player)';

  static Future<List<MetadataMatch>> search({required String title, String? artist, Duration? localDuration}) async {
    if (title.trim().isEmpty) return [];
    try {
      final queryParts = ['recording:"${_escape(title)}"'];
      if (artist != null && artist.trim().isNotEmpty) {
        queryParts.add('artist:"${_escape(artist)}"');
      }
      final uri = Uri.parse('https://musicbrainz.org/ws/2/recording').replace(queryParameters: {
        'query': queryParts.join(' AND '),
        'fmt': 'json',
        'limit': '10',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final recordings = json['recordings'] as List? ?? [];
      final matches = <MetadataMatch>[];
      for (final r in recordings) {
        final rec = r as Map<String, dynamic>;
        final recTitle = rec['title'] as String?;
        if (recTitle == null || recTitle.trim().isEmpty) continue;

        // Join every credited artist (with MusicBrainz's own "joinphrase",
        // e.g. " feat. ") instead of just the first one — a plain first-name
        // grab silently drops any featured artist from the result.
        final artistCredit = rec['artist-credit'] as List?;
        final recArtist = (artistCredit != null && artistCredit.isNotEmpty)
            ? artistCredit.map((ac) {
                final entry = ac as Map<String, dynamic>;
                return '${entry['name'] ?? ''}${entry['joinphrase'] ?? ''}';
              }).join().trim()
            : null;

        final release = _pickBestRelease(rec['releases'] as List?);
        final recAlbum = release?['title'] as String?;
        final dateStr = release?['date'] as String?;
        final year = (dateStr != null && dateStr.length >= 4) ? int.tryParse(dateStr.substring(0, 4)) : null;
        final releaseId = release?['id'] as String?;

        final lengthMs = rec['length'] as int?;

        final scoreRaw = rec['score'];
        final score = scoreRaw is int ? scoreRaw : int.tryParse('$scoreRaw') ?? 0;

        matches.add(MetadataMatch(
          title: recTitle.trim(),
          artist: (recArtist != null && recArtist.isNotEmpty ? recArtist : artist ?? '').trim(),
          album: (recAlbum ?? '').trim(),
          releaseYear: year,
          genre: _bestGenre(rec['tags'] as List?),
          duration: lengthMs != null ? Duration(milliseconds: lengthMs) : null,
          releaseId: releaseId,
          score: score,
        ));
      }

      // Best match first. MusicBrainz's own relevance score frequently ties
      // several candidates at 100 — when it does, break the tie by whichever
      // has a runtime closest to the local file's, since that's the
      // strongest available signal for which of several same-named
      // recordings this file actually is.
      matches.sort((a, b) {
        final scoreCmp = b.score.compareTo(a.score);
        if (scoreCmp != 0 || localDuration == null) return scoreCmp;
        final aDiff = a.duration == null ? null : (a.duration! - localDuration).abs();
        final bDiff = b.duration == null ? null : (b.duration! - localDuration).abs();
        if (aDiff == null && bDiff == null) return 0;
        if (aDiff == null) return 1;
        if (bDiff == null) return -1;
        return aDiff.compareTo(bDiff);
      });

      // Drop near-duplicates: the same recording frequently comes back once
      // per release it appears on — a deluxe reissue, a "best of"
      // compilation, a regional pressing — which used to flood the list
      // with entries differing only in a barely-visible detail.
      final seen = <String>{};
      return matches.where((m) {
        final key = '${m.title.toLowerCase()}|${m.artist.toLowerCase()}|${m.album.toLowerCase()}';
        return seen.add(key);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Picks the release most likely to be "the" album this recording belongs
  /// to, out of every release MusicBrainz has it filed under. Blindly taking
  /// the first entry tends to surface an obscure compilation or regional
  /// reissue rather than the actual original album, so this prefers an
  /// "Official" release, then the earliest release date among those.
  static Map<String, dynamic>? _pickBestRelease(List? releases) {
    if (releases == null || releases.isEmpty) return null;
    final list = releases.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) {
        final officialCmp =
            ((a['status'] as String?) == 'Official' ? 0 : 1).compareTo((b['status'] as String?) == 'Official' ? 0 : 1);
        if (officialCmp != 0) return officialCmp;
        final aDate = a['date'] as String? ?? '9999';
        final bDate = b['date'] as String? ?? '9999';
        return aDate.compareTo(bDate);
      });
    return list.first;
  }

  /// MusicBrainz "tags" are crowd-submitted folksonomy labels, not a curated
  /// genre field — a recording is just as likely to be tagged with a decade
  /// or a country as an actual genre. Picking whichever the API happened to
  /// list first produced nonsense results; the tag with the most user votes
  /// (`count`) is a better guess at an actual genre.
  static String? _bestGenre(List? tags) {
    if (tags == null || tags.isEmpty) return null;
    final list = tags.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => ((b['count'] as int?) ?? 0).compareTo((a['count'] as int?) ?? 0));
    return list.first['name'] as String?;
  }

  /// Fetches the front cover for a MusicBrainz release from the Cover Art
  /// Archive and saves it locally, keyed the same way the library scanner
  /// keys embedded artwork (md5 of `artist|album`) — so it lands at the same
  /// path already associated with this album and every track sharing it
  /// picks up the new art. Returns the saved file path, or null if no cover
  /// art is available for this release.
  static Future<String?> fetchAndSaveCoverArt({
    required String releaseId,
    required String artist,
    required String album,
  }) async {
    try {
      final uri = Uri.parse('https://coverartarchive.org/release/$releaseId/front');
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent, 'Accept': 'image/*'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

      final contentType = res.headers['content-type'] ?? '';
      final ext = contentType.contains('png') ? 'png' : 'jpg';
      return await ArtworkStore.saveBytes(res.bodyBytes, artist: artist, album: album, ext: ext);
    } catch (_) {
      return null;
    }
  }

  static String _escape(String s) => s.replaceAll('"', '\\"');
}
