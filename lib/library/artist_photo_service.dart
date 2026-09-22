import 'dart:convert';
import 'package:http/http.dart' as http;
import 'artwork_store.dart';

/// Looks up an artist's promo photo from Deezer's free, keyless public
/// search API and caches it locally, so the Artists grid can show a real
/// photo of the artist instead of one of their album covers.
class ArtistPhotoService {
  static const _placeholderHash = 'd41d8cd98f00b204e9800998ecf8427e';

  /// A local path to this artist's photo — the cached file if one was
  /// already downloaded, otherwise fetched from Deezer and cached for next
  /// time. Null if this artist has no photo available.
  static Future<String?> photoFor(String artist) async {
    final cached = await ArtworkStore.cachedArtistPhoto(artist);
    if (cached != null) return cached;
    return _fetchFromNetwork(artist);
  }

  static Future<String?> _fetchFromNetwork(String artist) async {
    try {
      final uri = Uri.parse('https://api.deezer.com/search/artist').replace(queryParameters: {
        'q': artist,
        'limit': '1',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final data = json['data'] as List? ?? [];
      if (data.isEmpty) return null;

      final pictureUrl = (data.first as Map<String, dynamic>)['picture_big'] as String?;
      // Deezer serves this exact image (keyed by the md5 of an empty
      // string) as a generic silhouette placeholder for artists it has no
      // real photo of — skip it rather than caching a fake "photo".
      if (pictureUrl == null || pictureUrl.contains(_placeholderHash)) return null;

      final imgRes = await http.get(Uri.parse(pictureUrl)).timeout(const Duration(seconds: 10));
      if (imgRes.statusCode != 200 || imgRes.bodyBytes.isEmpty) return null;

      return await ArtworkStore.saveArtistBytes(imgRes.bodyBytes, artist: artist, ext: 'jpg');
    } catch (_) {
      return null;
    }
  }
}
