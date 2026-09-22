import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' show md5;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Saves artwork bytes to the app's local artwork cache, keyed the same way
/// the library scanner keys embedded artwork (md5 of `artist|album`) — so
/// it lands at the path already associated with an album and every track
/// sharing it picks up the change, whether the art came from an online
/// lookup or the user picked a file by hand.
class ArtworkStore {
  static Future<String> saveBytes(
    List<int> bytes, {
    required String artist,
    required String album,
    required String ext,
  }) async {
    final artworkDir = Directory(p.join((await getApplicationSupportDirectory()).path, 'artwork'));
    if (!await artworkDir.exists()) await artworkDir.create(recursive: true);

    final key = md5.convert(utf8.encode('$artist|$album')).toString();
    final artFile = File(p.join(artworkDir.path, '$key.$ext'));
    await artFile.writeAsBytes(bytes);
    return artFile.path;
  }

  static Future<Directory> _artistPhotoDir() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'artist_photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Saves a fetched artist photo, keyed by md5 of the artist name alone
  /// (unlike album art, an artist photo isn't tied to any one album).
  static Future<String> saveArtistBytes(List<int> bytes, {required String artist, required String ext}) async {
    final dir = await _artistPhotoDir();
    final key = md5.convert(utf8.encode(artist)).toString();
    final file = File(p.join(dir.path, '$key.$ext'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// The already-downloaded photo for this artist, if any — checked before
  /// hitting the network again for the same name.
  static Future<String?> cachedArtistPhoto(String artist) async {
    final dir = await _artistPhotoDir();
    final key = md5.convert(utf8.encode(artist)).toString();
    for (final ext in const ['jpg', 'png']) {
      final file = File(p.join(dir.path, '$key.$ext'));
      if (await file.exists()) return file.path;
    }
    return null;
  }
}
