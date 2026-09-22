import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'artwork_store.dart';

/// One track pulled from a YouTube/YouTube Music playlist, before it's been
/// saved to the local library.
class YoutubePlaylistTrack {
  final String videoId;
  final String title;
  final String artist;
  final Duration duration;
  final String thumbnailUrl;

  const YoutubePlaylistTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnailUrl,
  });
}

/// A resolved, playable audio stream: the direct CDN URL plus whatever HTTP
/// headers yt-dlp says are required to actually fetch it. YouTube's CDN
/// signs these URLs to a specific client context and rejects requests that
/// don't carry that client's headers (mpv otherwise sees a bare "stream:
/// Failed to open"/403) — so [headers] must be passed to the player, not
/// just used to fetch [url] once.
class YoutubeAudioStream {
  final String url;
  final Map<String, String> headers;
  const YoutubeAudioStream({required this.url, required this.headers});
}

/// Pulls playlist contents and audio streams from YouTube/YouTube Music by
/// shelling out to `yt-dlp` (Linux desktop only — see `youtubePlaylistImportAvailable`
/// in main.dart). There's no public API for either, and `yt-dlp` is what
/// actually keeps up with YouTube's anti-scraping countermeasures (signature
/// ciphers, client selection, JS/PO-token challenges) — a hand-rolled Dart
/// reimplementation (this used to wrap `youtube_explode_dart`) falls behind
/// and needs its own workarounds for every new countermeasure. Playback
/// (`resolveAudioStream`) needs an internet connection every time, since the
/// URLs it returns expire after a few hours — these tracks always stream,
/// there's no offline/download path.
class YoutubeService {
  /// Pulls a playlist ID out of a YouTube Music / YouTube playlist URL
  /// (`music.youtube.com`, `www.youtube.com`, or a bare `list=` id). Returns
  /// null if nothing playlist-shaped is found.
  static String? extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    String? id = Uri.tryParse(trimmed)?.queryParameters['list'];
    id ??= RegExp(r'[?&]list=([A-Za-z0-9_-]+)').firstMatch(trimmed)?.group(1);
    if (id == null && RegExp(r'^[A-Za-z0-9_-]{10,}$').hasMatch(trimmed)) {
      id = trimmed;
    }
    if (id == null || id.isEmpty) return null;

    // YouTube Music playlist links prefix the id with "VL"; the regular
    // playlist endpoint yt-dlp reads wants it without that prefix.
    if (id.startsWith('VL')) id = id.substring(2);
    return id;
  }

  /// Pulls a video ID out of a plain YouTube/YouTube Music watch link
  /// (`youtube.com/watch?v=`, `music.youtube.com/watch?v=`, or the short
  /// `youtu.be/<id>` form) — used for a single-song play/download, as
  /// opposed to [extractPlaylistId] for a playlist or album link. Returns
  /// null if nothing video-shaped is found. Callers should try
  /// [extractPlaylistId] first, since a playlist link opened from inside a
  /// playlist can also carry a `v=` param.
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    String? id = uri?.queryParameters['v'];
    if (id == null && uri != null && uri.host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      id = uri.pathSegments.first;
    }
    id ??= RegExp(r'(?:[?&]v=|youtu\.be/)([A-Za-z0-9_-]{11})').firstMatch(trimmed)?.group(1);
    if (id == null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(trimmed)) {
      id = trimmed;
    }
    return id;
  }

  /// Fetches a single video's title/artist/duration/thumbnail — used to
  /// build a track for a single-song play/download, where [fetchPlaylist]'s
  /// flat-playlist listing doesn't apply.
  static Future<YoutubePlaylistTrack> fetchVideoInfo(String videoId) async {
    final data = await _runYtdlpJson([
      '--skip-download',
      '--dump-json',
      'https://www.youtube.com/watch?v=$videoId',
    ]);

    final durationSecs = (data['duration'] as num?)?.toDouble();
    return YoutubePlaylistTrack(
      videoId: videoId,
      title: (data['title'] as String?)?.trim() ?? 'Unknown title',
      artist: ((data['uploader'] ?? data['channel']) as String?)?.trim() ?? '',
      duration: durationSecs != null ? Duration(milliseconds: (durationSecs * 1000).round()) : Duration.zero,
      thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
    );
  }

  /// Fetches a playlist's title and track list in one `yt-dlp` call
  /// (`--flat-playlist` skips per-video extraction, so this stays fast even
  /// for large playlists). Title is null if it couldn't be read; caller
  /// picks a generic name in that case.
  static Future<({String? title, List<YoutubePlaylistTrack> tracks})> fetchPlaylist(String playlistId) async {
    final data = await _runYtdlpJson([
      '--flat-playlist',
      '--dump-single-json',
      'https://www.youtube.com/playlist?list=$playlistId',
    ]);

    final title = (data['title'] as String?)?.trim();
    final entries = (data['entries'] as List?) ?? const [];
    final tracks = <YoutubePlaylistTrack>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      final videoId = entry['id'] as String?;
      if (videoId == null || videoId.isEmpty) continue;
      final durationSecs = (entry['duration'] as num?)?.toDouble();
      tracks.add(YoutubePlaylistTrack(
        videoId: videoId,
        title: (entry['title'] as String?)?.trim() ?? 'Unknown title',
        artist: (entry['channel'] ?? entry['uploader'] ?? '') as String,
        duration: durationSecs != null ? Duration(milliseconds: (durationSecs * 1000).round()) : Duration.zero,
        // yt-dlp's flat-playlist thumbnails are inconsistent across
        // extractor versions; this pattern is stable and needs no auth.
        thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      ));
    }
    return (title: title == null || title.isEmpty ? null : title, tracks: tracks);
  }

  /// Resolves a fresh, playable, audio-only stream for a video. Must be
  /// called right before playing — the URL is short-lived and can't be
  /// cached for later.
  static Future<YoutubeAudioStream> resolveAudioStream(String videoId) async {
    final data = await _runYtdlpJson([
      '-f',
      'bestaudio',
      '--dump-json',
      'https://www.youtube.com/watch?v=$videoId',
    ]);

    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception("yt-dlp didn't return a playable stream for that video.");
    }
    final rawHeaders = (data['http_headers'] as Map?) ?? const {};
    final headers = rawHeaders.map((key, value) => MapEntry(key.toString(), value.toString()));
    return YoutubeAudioStream(url: url, headers: headers);
  }

  /// Downloads a video's audio as a real local mp3 into [outputDir] (created
  /// if it doesn't exist yet), embedding title/artist/thumbnail metadata so
  /// the local library scanner picks it up the same as any other file —
  /// unlike [resolveAudioStream], this needs `ffmpeg` on top of `yt-dlp`
  /// (for the audio extraction/mp3 conversion and metadata muxing).
  /// Returns the final saved file path.
  static Future<String> downloadAudio(String videoId, String outputDir) async {
    final dir = Directory(outputDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    final ProcessResult result;
    try {
      result = await Process.run('yt-dlp', [
        '--no-warnings',
        '--quiet',
        '--no-playlist',
        '-x',
        '--audio-format',
        'mp3',
        '--embed-metadata',
        '--embed-thumbnail',
        '-o',
        p.join(outputDir, '%(title)s [%(id)s].%(ext)s'),
        '--print',
        'after_move:filepath',
        'https://www.youtube.com/watch?v=$videoId',
      ]);
    } on ProcessException {
      throw Exception("yt-dlp isn't installed — downloading needs it (e.g. `sudo pacman -S yt-dlp`).");
    }
    if (result.exitCode != 0) {
      throw Exception('yt-dlp failed: ${result.stderr}');
    }
    // --print writes the resolved path as the last line of stdout, after any
    // remaining progress/warning noise that --quiet doesn't fully suppress.
    final path = (result.stdout as String).trim().split('\n').last.trim();
    if (path.isEmpty) {
      throw Exception("yt-dlp didn't report where it saved the file.");
    }
    return path;
  }

  /// Turns a playlist/album title into something safe to use as a folder
  /// name: strips characters that are illegal (or awkward) on common
  /// filesystems, collapses whitespace, and trims trailing dots/spaces
  /// (which Windows rejects). Falls back to a generic name if that leaves
  /// nothing usable.
  static String sanitizeFolderName(String name) {
    var cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    while (cleaned.endsWith('.') || cleaned.endsWith(' ')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned.isEmpty ? 'YouTube Playlist' : cleaned;
  }

  /// Runs `yt-dlp` with the given args and parses its stdout as JSON.
  /// Surfaces a clear error if `yt-dlp` itself isn't installed, rather than
  /// the raw "No such file or directory" `ProcessException`.
  static Future<Map<String, dynamic>> _runYtdlpJson(List<String> args) async {
    final ProcessResult result;
    try {
      result = await Process.run('yt-dlp', ['--no-warnings', ...args]);
    } on ProcessException {
      throw Exception("yt-dlp isn't installed — YouTube playlists need it (e.g. `sudo pacman -S yt-dlp`).");
    }
    if (result.exitCode != 0) {
      throw Exception('yt-dlp failed: ${result.stderr}');
    }
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  /// Downloads a video's thumbnail and saves it through the shared artwork
  /// cache, same as any other online-fetched cover.
  static Future<String?> cacheThumbnail(String videoId, String thumbnailUrl, String artist) async {
    try {
      final res = await http.get(Uri.parse(thumbnailUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final contentType = res.headers['content-type'] ?? '';
      final ext = contentType.contains('png') ? 'png' : 'jpg';
      // Keyed per-video (not per-album, unlike local scans) since a YouTube
      // import doesn't group tracks into real albums.
      return await ArtworkStore.saveBytes(res.bodyBytes, artist: artist, album: 'yt:$videoId', ext: ext);
    } catch (_) {
      return null;
    }
  }
}
