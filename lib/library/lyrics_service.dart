import 'dart:convert';
import 'package:http/http.dart' as http;

class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

/// Parsed lyrics: either a synced (LRC) line list, or plain unsynced text.
class ParsedLyrics {
  final List<LyricLine> syncedLines;
  final String? plainText;
  bool get isSynced => syncedLines.isNotEmpty;
  bool get isEmpty => syncedLines.isEmpty && (plainText == null || plainText!.trim().isEmpty);

  const ParsedLyrics({this.syncedLines = const [], this.plainText});
  static const empty = ParsedLyrics();
}

final _lrcLineRegex = RegExp(r'^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$');

/// Reads embedded lyrics (which may already be plain text or LRC-formatted)
/// and, failing that, fetches synced lyrics from lrclib.net's free public
/// API when online. lrclib requires no API key/auth.
class LyricsService {
  static ParsedLyrics parse(String raw) {
    final lines = raw.split('\n');
    final synced = <LyricLine>[];
    for (final line in lines) {
      final match = _lrcLineRegex.firstMatch(line.trim());
      if (match == null) continue;
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fracStr = match.group(3) ?? '0';
      final millis = int.parse(fracStr.padRight(3, '0').substring(0, 3));
      final text = match.group(4)!.trim();
      synced.add(LyricLine(
        Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
        text,
      ));
    }
    if (synced.isNotEmpty) {
      synced.sort((a, b) => a.time.compareTo(b.time));
      return ParsedLyrics(syncedLines: synced);
    }
    return ParsedLyrics(plainText: raw.trim().isEmpty ? null : raw.trim());
  }

  // YouTube titles/channels carry noise lrclib's records don't, so a raw
  // lookup misses: "Song (Official Video)", "Artist - Topic", "Artist - Song".
  static final _titleNoise = RegExp(
    r'\s*[\(\[][^\)\]]*(official|video|audio|lyric|visualizer|\bhd\b|4k)[^\)\]]*[\)\]]',
    caseSensitive: false,
  );
  static final _artistNoise = RegExp(r'\s*(-\s*topic|vevo)$', caseSensitive: false);

  static Future<ParsedLyrics?> fetchFromLrclib({
    required String title,
    required String artist,
    required String album,
    required Duration duration,
  }) async {
    final cleanTitle = title.replaceAll(_titleNoise, '').trim();
    final cleanArtist = artist.replaceAll(_artistNoise, '').trim();
    final exact = await _fetchExact(title: cleanTitle, artist: cleanArtist, album: album, duration: duration);
    if (exact != null) return exact;

    // "Artist - Song" packed into the title (common for YouTube uploads).
    final split = cleanTitle.split(' - ');
    if (split.length == 2) return _searchFallback(split[1].trim(), split[0].trim());
    return null;
  }

  static Future<ParsedLyrics?> _fetchExact({
    required String title,
    required String artist,
    required String album,
    required Duration duration,
  }) async {
    try {
      final uri = Uri.parse('https://lrclib.net/api/get').replace(queryParameters: {
        'track_name': title,
        'artist_name': artist,
        'album_name': album,
        'duration': duration.inSeconds.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return await _searchFallback(title, artist);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return _fromLrclibJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<ParsedLyrics?> _searchFallback(String title, String artist) async {
    try {
      final uri = Uri.parse('https://lrclib.net/api/search').replace(queryParameters: {
        'track_name': title,
        'artist_name': artist,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final results = jsonDecode(res.body) as List;
      if (results.isEmpty) return null;
      return _fromLrclibJson(results.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static ParsedLyrics? _fromLrclibJson(Map<String, dynamic> json) {
    final synced = json['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) return parse(synced);
    final plain = json['plainLyrics'] as String?;
    if (plain != null && plain.trim().isNotEmpty) return ParsedLyrics(plainText: plain.trim());
    return null;
  }
}
