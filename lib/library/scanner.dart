import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart' show md5;
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'db.dart';

const kSupportedAudioExtensions = {
  '.mp3',
  '.flac',
  '.wav',
  '.aif',
  '.aiff',
  '.aifc',
  '.m4a',
  '.mp4',
  '.aac',
  '.ogg',
  '.opus',
};

/// Recursively scans a folder for audio files, extracts metadata (and cover
/// art) via audio_metadata_reader, and upserts everything into the local
/// SQLite library. Reports progress via [onProgress] (files processed so far).
class LibraryScanner {
  static Future<void> scanFolder(String folderPath, {void Function(int count)? onProgress}) async {
    await LibraryDatabase.addScannedFolder(folderPath);
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    final artworkDir = Directory(p.join((await getApplicationSupportDirectory()).path, 'artwork'));
    if (!await artworkDir.exists()) await artworkDir.create(recursive: true);

    var count = 0;
    final presentPaths = <String>{};
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!kSupportedAudioExtensions.contains(ext)) continue;
      // Recorded before the import attempt below, so a file that fails to
      // parse this pass (transient/corrupt-tag read error) still counts as
      // present and isn't pruned as missing.
      presentPaths.add(entity.path);

      try {
        await _importFile(entity, artworkDir.path);
        count++;
        onProgress?.call(count);
      } catch (_) {
        // Skip files that fail to parse (corrupt tags, unsupported variant)
        // rather than aborting the whole scan.
      }
    }

    await LibraryDatabase.removeMissingTracksInFolder(folderPath, presentPaths);
  }

  /// Imports a single audio file already on disk the same way a folder scan
  /// would — reads its metadata/artwork and upserts it into the library.
  /// Used for a file just downloaded from YouTube, which needs to end up in
  /// the library the same way a locally-scanned file would, without waiting
  /// for a full folder rescan. Returns the track's id. [youtubeVideoId], when
  /// the file came from a YouTube download, is stamped onto the row so a
  /// later playlist/track download can recognize this song was already
  /// fetched and skip re-downloading it.
  static Future<int> importSingleFile(File file, {String? youtubeVideoId}) async {
    final artworkDir = Directory(p.join((await getApplicationSupportDirectory()).path, 'artwork'));
    if (!await artworkDir.exists()) await artworkDir.create(recursive: true);
    return _importFile(file, artworkDir.path, youtubeVideoId: youtubeVideoId);
  }

  static Future<int> _importFile(File file, String artworkDirPath, {String? youtubeVideoId}) async {
    final metadata = readMetadata(file, getImage: true);

    final title = (metadata.title?.trim().isNotEmpty ?? false)
        ? metadata.title!.trim()
        : p.basenameWithoutExtension(file.path);
    final artist = (metadata.artist?.trim().isNotEmpty ?? false) ? metadata.artist!.trim() : 'Unknown Artist';
    final album = (metadata.album?.trim().isNotEmpty ?? false) ? metadata.album!.trim() : 'Unknown Album';

    String? artworkPath;
    if (metadata.pictures.isNotEmpty) {
      final key = md5.convert(utf8.encode('$artist|$album')).toString();
      final ext = metadata.pictures.first.mimetype.contains('png') ? 'png' : 'jpg';
      final artFile = File(p.join(artworkDirPath, '$key.$ext'));
      if (!await artFile.exists()) {
        await artFile.writeAsBytes(metadata.pictures.first.bytes);
      }
      artworkPath = artFile.path;
    }

    // Group by the track's main (first-listed) artist so a collab/feature
    // track lands in the same album as the rest of the record instead of
    // forking off a separate one-off album entry.
    final albumArtist = LibraryDatabase.primaryArtist(artist);
    final albumId = await LibraryDatabase.upsertAlbum(album, albumArtist, artworkPath, metadata.year?.year);

    final trackNumber = metadata.trackNumber ?? 0;
    // A file at a brand-new path that's actually the same song already in
    // the library under a different filename (re-downloaded, copied twice,
    // etc.) — skip adding a duplicate row for it. Track number 0 means
    // "unknown", so it's excluded: several genuinely different, untagged
    // singles can all land on 0 and would otherwise look like duplicates of
    // each other.
    if (trackNumber != 0) {
      final duplicateId = await LibraryDatabase.findDuplicateTrack(
        title: title,
        artist: artist,
        albumId: albumId,
        trackNumber: trackNumber,
        excludingPath: file.path,
      );
      if (duplicateId != null) return duplicateId;
    }

    return LibraryDatabase.upsertTrack(
      path: file.path,
      title: title,
      artist: artist,
      album: album,
      albumId: albumId,
      trackNumber: trackNumber,
      discNumber: metadata.discNumber ?? 1,
      duration: metadata.duration ?? Duration.zero,
      artworkPath: artworkPath,
      lyrics: metadata.lyrics,
      genre: metadata.genres.isNotEmpty ? metadata.genres.first : null,
      youtubeVideoId: youtubeVideoId,
    );
  }
}
