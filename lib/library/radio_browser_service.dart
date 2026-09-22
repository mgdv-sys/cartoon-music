import 'dart:convert';
import 'package:http/http.dart' as http;

/// A station result from the Radio Browser directory search — not yet
/// saved; the caller turns it into a [RadioStation] via
/// `AppState.addRadioStation` if the user picks it.
class RadioBrowserResult {
  final String stationUuid;
  final String name;
  final String url;
  final String country;
  final String tags;
  final String codec;
  final int bitrate;
  final int votes;
  final String? favicon;

  const RadioBrowserResult({
    required this.stationUuid,
    required this.name,
    required this.url,
    required this.country,
    required this.tags,
    required this.codec,
    required this.bitrate,
    required this.votes,
    this.favicon,
  });

  factory RadioBrowserResult.fromJson(Map<String, dynamic> json) => RadioBrowserResult(
        stationUuid: json['stationuuid'] as String? ?? '',
        name: (json['name'] as String? ?? '').trim(),
        url: (json['url_resolved'] as String?)?.trim().isNotEmpty == true
            ? json['url_resolved'] as String
            : (json['url'] as String? ?? ''),
        country: json['country'] as String? ?? '',
        tags: json['tags'] as String? ?? '',
        codec: json['codec'] as String? ?? '',
        bitrate: json['bitrate'] as int? ?? 0,
        votes: json['votes'] as int? ?? 0,
        favicon: (json['favicon'] as String?)?.trim().isEmpty == true ? null : json['favicon'] as String?,
      );

  String get subtitle {
    final parts = <String>[
      if (country.isNotEmpty) country,
      if (codec.isNotEmpty && bitrate > 0) '$codec ${bitrate}kbps',
    ];
    return parts.join(' · ');
  }
}

/// Searches the free, community-run Radio Browser directory
/// (radio-browser.info) for real internet radio stations — tens of
/// thousands worldwide, each already checked for a working stream URL.
/// No API key needed, but their usage guidelines ask for an identifying
/// User-Agent. Tries a short list of known mirror servers in order, since
/// any single one can be temporarily down.
class RadioBrowserService {
  static const _mirrors = [
    'de1.api.radio-browser.info',
    'nl1.api.radio-browser.info',
    'at1.api.radio-browser.info',
  ];
  static const _userAgent = 'Playah/1.0 (Flutter local music player)';

  static Future<List<RadioBrowserResult>> search({
    String? name,
    String? country,
    int limit = 40,
  }) async {
    final queryParameters = {
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (country != null && country.trim().isNotEmpty) 'country': country.trim(),
      'limit': limit.toString(),
      'hidebroken': 'true',
      'order': 'votes',
      'reverse': 'true',
    };

    for (final mirror in _mirrors) {
      try {
        final uri = Uri.https(mirror, '/json/stations/search', queryParameters);
        final res = await http
            .get(uri, headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final results = jsonDecode(res.body) as List;
        return results
            .map((e) => RadioBrowserResult.fromJson(e as Map<String, dynamic>))
            .where((s) => s.name.isNotEmpty && s.url.isNotEmpty)
            .toList();
      } catch (_) {
        continue; // try the next mirror
      }
    }
    throw Exception('Couldn\'t reach the station directory. Check your connection and try again.');
  }
}
