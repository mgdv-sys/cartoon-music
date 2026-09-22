import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'models.dart';

/// SQLite-backed local library store: tracks, albums, playlists, favorites,
/// and play history. Initializes the FFI sqflite backend on desktop Linux
/// (Android/iOS use the native sqflite plugin automatically).
class LibraryDatabase {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'library.db');
    _db = await openDatabase(
      dbPath,
      version: 8,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE albums ADD COLUMN release_year INTEGER');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE radio_stations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              url TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute("ALTER TABLE radio_stations ADD COLUMN type TEXT NOT NULL DEFAULT 'audio'");
        }
        if (oldVersion < 5) {
          await _seedOnlineRadioPh(db);
        }
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE radio_stations ADD COLUMN logo_url TEXT');
        }
        if (oldVersion < 7) {
          await db.execute('ALTER TABLE tracks ADD COLUMN genre TEXT');
        }
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE tracks ADD COLUMN youtube_video_id TEXT');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE albums (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            artist TEXT NOT NULL,
            artwork_path TEXT,
            release_year INTEGER,
            UNIQUE(name, artist)
          )
        ''');
        await db.execute('''
          CREATE TABLE tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            album_id INTEGER,
            track_number INTEGER DEFAULT 0,
            disc_number INTEGER DEFAULT 1,
            duration_ms INTEGER DEFAULT 0,
            artwork_path TEXT,
            lyrics TEXT,
            genre TEXT,
            play_count INTEGER DEFAULT 0,
            last_played_at INTEGER,
            is_favorite INTEGER DEFAULT 0,
            date_added INTEGER NOT NULL,
            youtube_video_id TEXT,
            FOREIGN KEY(album_id) REFERENCES albums(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE playlist_tracks (
            playlist_id INTEGER NOT NULL,
            track_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, track_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE scanned_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE radio_stations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'audio',
            logo_url TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        await _seedOnlineRadioPh(db);
      },
    );
    return _db!;
  }

  /// One-time seed for a user-requested station: onlineradio.ph is a
  /// station-directory webpage (not a raw audio stream), so it has to be a
  /// `web` link opened in the embedded/browser player, not `audio`.
  static Future<void> _seedOnlineRadioPh(Database db) async {
    final existing = await db.query('radio_stations', where: 'url = ?', whereArgs: ['https://onlineradio.ph/']);
    if (existing.isNotEmpty) return;
    await db.insert('radio_stations', {
      'name': 'Online Radio PH',
      'url': 'https://onlineradio.ph/',
      'type': 'web',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static LibraryTrack _trackFromRow(Map<String, Object?> r) => LibraryTrack(
        id: r['id'] as int,
        path: r['path'] as String,
        title: r['title'] as String,
        artist: r['artist'] as String,
        album: r['album'] as String,
        albumId: r['album_id'] as int?,
        trackNumber: r['track_number'] as int? ?? 0,
        discNumber: r['disc_number'] as int? ?? 1,
        duration: Duration(milliseconds: r['duration_ms'] as int? ?? 0),
        artworkPath: r['artwork_path'] as String?,
        lyrics: r['lyrics'] as String?,
        genre: r['genre'] as String?,
        playCount: r['play_count'] as int? ?? 0,
        lastPlayedAt: r['last_played_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(r['last_played_at'] as int)
            : null,
        isFavorite: (r['is_favorite'] as int? ?? 0) == 1,
        dateAdded: DateTime.fromMillisecondsSinceEpoch(r['date_added'] as int),
        youtubeVideoId: r['youtube_video_id'] as String?,
      );

  /// Separators used by taggers to pack more than one performer into a
  /// single artist field: "Artist A, Artist B", "Artist A feat. Artist B",
  /// "Artist A / Artist B", "Artist A & Artist B"...
  static final RegExp _multiArtistSplit = RegExp(
    r'\s*(?:,|;|/|&|\bfeat\.?\b|\bfeaturing\b|\bft\.?\b|\bvs\.?\b)\s*',
    caseSensitive: false,
  );

  /// The first-listed artist in a possibly multi-artist tag (e.g.
  /// "Artist A, Artist B" or "Artist A feat. Artist B" -> "Artist A").
  /// Used as the album's grouping key and "main artist", so a collab track
  /// doesn't fork off a duplicate album entry and albums sort by that one
  /// main artist. A single-artist tag passes through unchanged.
  static String primaryArtist(String artist) {
    final parts = artist.split(_multiArtistSplit).map((p) => p.trim()).where((p) => p.isNotEmpty);
    return parts.isEmpty ? artist : parts.first;
  }

  static Future<int> upsertAlbum(String name, String artist, String? artworkPath, int? releaseYear) async {
    final db = await instance;
    final existing = await db.query('albums',
        where: 'name = ? AND artist = ?', whereArgs: [name, artist], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      final updates = <String, Object?>{};
      if (artworkPath != null && existing.first['artwork_path'] == null) updates['artwork_path'] = artworkPath;
      if (releaseYear != null && existing.first['release_year'] == null) updates['release_year'] = releaseYear;
      if (updates.isNotEmpty) {
        await db.update('albums', updates, where: 'id = ?', whereArgs: [id]);
      }
      return id;
    }
    return db.insert('albums',
        {'name': name, 'artist': artist, 'artwork_path': artworkPath, 'release_year': releaseYear});
  }

  /// Returns the track's id — the new row's, or the existing row's (with its
  /// metadata refreshed) if this path was already imported. Refreshing on
  /// every scan means a file whose tags changed on disk since the last scan
  /// (retagged, re-encoded in place) picks up the new metadata instead of
  /// being silently skipped. `artwork_path`/`lyrics` are only overwritten
  /// when the rescan actually found a new value, so a file that temporarily
  /// loses its embedded art/lyrics doesn't blank out what was already saved.
  static Future<int> upsertTrack({
    required String path,
    required String title,
    required String artist,
    required String album,
    required int albumId,
    required int trackNumber,
    required int discNumber,
    required Duration duration,
    required String? artworkPath,
    required String? lyrics,
    String? genre,
    String? youtubeVideoId,
  }) async {
    final db = await instance;
    final existing = await db.query('tracks', where: 'path = ?', whereArgs: [path], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      final oldAlbumId = existing.first['album_id'] as int?;
      await db.update(
        'tracks',
        {
          'title': title,
          'artist': artist,
          'album': album,
          'album_id': albumId,
          'track_number': trackNumber,
          'disc_number': discNumber,
          'duration_ms': duration.inMilliseconds,
          if (artworkPath != null) 'artwork_path': artworkPath,
          if (lyrics != null) 'lyrics': lyrics,
          'genre': genre,
          if (youtubeVideoId != null) 'youtube_video_id': youtubeVideoId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      // A retag can move the track to a different album — drop the old
      // album row if this was its last track, same as a manual edit does.
      if (oldAlbumId != null && oldAlbumId != albumId) {
        final remaining = await db.query('tracks', where: 'album_id = ?', whereArgs: [oldAlbumId], limit: 1);
        if (remaining.isEmpty) {
          await db.delete('albums', where: 'id = ?', whereArgs: [oldAlbumId]);
        }
      }
      return id;
    }
    return db.insert('tracks', {
      'path': path,
      'title': title,
      'artist': artist,
      'album': album,
      'album_id': albumId,
      'track_number': trackNumber,
      'disc_number': discNumber,
      'duration_ms': duration.inMilliseconds,
      'artwork_path': artworkPath,
      'lyrics': lyrics,
      'genre': genre,
      'youtube_video_id': youtubeVideoId,
      'date_added': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// The id of an already-*downloaded* (real local file, not a still-
  /// streaming `youtube:<id>` placeholder) track sourced from this YouTube
  /// video, if one exists — used to skip re-downloading a song that's
  /// already in the library under a different playlist/import.
  static Future<int?> downloadedTrackIdForYoutubeVideo(String videoId) async {
    final db = await instance;
    final rows = await db.query(
      'tracks',
      where: "youtube_video_id = ? AND path NOT LIKE 'youtube:%'",
      whereArgs: [videoId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Inserts (or, if this video was imported before, reuses) a row for a
  /// YouTube-sourced track. `path` is always set to a placeholder
  /// (`youtube:<videoId>`) rather than a real file, since these tracks only
  /// ever stream — unique per video, which is all the `path UNIQUE`
  /// constraint needs. Deduped by `youtube_video_id` so re-importing the
  /// same playlist, or a track that appears in two different playlists,
  /// reuses one row.
  static Future<int> upsertYoutubeTrack({
    required String videoId,
    required String title,
    required String artist,
    required String album,
    required int trackNumber,
    required Duration duration,
  }) async {
    final db = await instance;
    final existing = await db.query('tracks', where: 'youtube_video_id = ?', whereArgs: [videoId], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return db.insert(
      'tracks',
      {
        'path': 'youtube:$videoId',
        'title': title,
        'artist': artist,
        'album': album,
        'track_number': trackNumber,
        'duration_ms': duration.inMilliseconds,
        'youtube_video_id': videoId,
        'date_added': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Fills in an imported YouTube track's artwork once fetched, without
  /// disturbing anything else — used while a playlist import's thumbnails
  /// are still loading in the background after playback has already started.
  static Future<void> setTrackArtwork(int trackId, String artworkPath) async {
    final db = await instance;
    await db.update('tracks', {'artwork_path': artworkPath}, where: 'id = ?', whereArgs: [trackId]);
  }

  /// A track already in the library that looks like the same song as a file
  /// about to be imported — same title, artist, album, and track number
  /// (title is required too: a badly-tagged album can have several
  /// different songs all claiming "track 1", so album+track-number alone
  /// isn't a safe match). Used to skip re-importing a song that was
  /// downloaded/copied twice under a different filename, instead of
  /// doubling it up in the library.
  static Future<int?> findDuplicateTrack({
    required String title,
    required String artist,
    required int albumId,
    required int trackNumber,
    required String excludingPath,
  }) async {
    final db = await instance;
    final rows = await db.query(
      'tracks',
      where: 'title = ? COLLATE NOCASE AND artist = ? COLLATE NOCASE AND album_id = ? AND track_number = ? AND path != ?',
      whereArgs: [title, artist, albumId, trackNumber, excludingPath],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Edits a track's metadata fields. If the artist/album changed, the track
  /// is re-linked to (or a new row created for) the matching album, and the
  /// old album row is dropped if it's now empty.
  static Future<void> updateTrackMetadata(
    int trackId, {
    required String title,
    required String artist,
    required String album,
    required int trackNumber,
    String? genre,
    int? releaseYear,
    String? artworkPath,
  }) async {
    final db = await instance;
    final rows = await db.query('tracks', where: 'id = ?', whereArgs: [trackId], limit: 1);
    if (rows.isEmpty) return;
    final oldAlbumId = rows.first['album_id'] as int?;
    final existingArtwork = rows.first['artwork_path'] as String?;

    final albumId = await upsertAlbum(album, primaryArtist(artist), artworkPath ?? existingArtwork, releaseYear);
    await db.update(
      'tracks',
      {
        'title': title,
        'artist': artist,
        'album': album,
        'album_id': albumId,
        'track_number': trackNumber,
        'genre': genre,
        if (artworkPath != null) 'artwork_path': artworkPath,
      },
      where: 'id = ?',
      whereArgs: [trackId],
    );

    // An explicit new cover (from autofill) should overwrite whatever the
    // album already had — upsertAlbum above only fills in a *missing*
    // artwork_path, it won't replace an existing one.
    if (artworkPath != null) {
      await db.update('albums', {'artwork_path': artworkPath}, where: 'id = ?', whereArgs: [albumId]);
    }

    if (oldAlbumId != null && oldAlbumId != albumId) {
      final remaining = await db.query('tracks', where: 'album_id = ?', whereArgs: [oldAlbumId], limit: 1);
      if (remaining.isEmpty) {
        await db.delete('albums', where: 'id = ?', whereArgs: [oldAlbumId]);
      }
    }
  }

  /// Removes a track's DB row (and its playlist memberships). Does not touch
  /// the file on disk — callers that also want the file deleted handle that
  /// themselves, since that's an irreversible filesystem action.
  static Future<void> deleteTrack(int trackId) async {
    final db = await instance;
    final rows = await db.query('tracks', where: 'id = ?', whereArgs: [trackId], limit: 1);
    if (rows.isEmpty) return;
    final albumId = rows.first['album_id'] as int?;

    await db.delete('playlist_tracks', where: 'track_id = ?', whereArgs: [trackId]);
    await db.delete('tracks', where: 'id = ?', whereArgs: [trackId]);

    if (albumId != null) {
      final remaining = await db.query('tracks', where: 'album_id = ?', whereArgs: [albumId], limit: 1);
      if (remaining.isEmpty) {
        await db.delete('albums', where: 'id = ?', whereArgs: [albumId]);
      }
    }
  }

  /// Drops any local track rows whose file lives inside [folderPath] but
  /// wasn't seen during this scan — i.e. it was deleted, moved, or renamed
  /// on disk since the last scan. Without this, a scan only ever adds rows,
  /// so a track whose file is gone stays in the library forever (stale
  /// entry, dead path). YouTube-streamed rows have no real file and are
  /// left untouched.
  static Future<void> removeMissingTracksInFolder(String folderPath, Set<String> presentPaths) async {
    final db = await instance;
    final rows = await db.query('tracks', where: _excludeYoutubeStreams);
    for (final row in rows) {
      final path = row['path'] as String;
      if (!p.isWithin(folderPath, path)) continue;
      if (presentPaths.contains(path)) continue;
      await deleteTrack(row['id'] as int);
    }
  }

  /// YouTube imports are real `tracks` rows (so playlists/queue/favorites
  /// work), but they only ever surface on the Playlists screen (via
  /// `tracksForPlaylist`) — every other library-wide view filters them out
  /// with this.
  static const _excludeYoutubeStreams = "path NOT LIKE 'youtube:%'";

  static Future<List<LibraryTrack>> allTracks({String orderBy = 'artist, album, track_number'}) async {
    final db = await instance;
    final rows = await db.query('tracks', where: _excludeYoutubeStreams, orderBy: orderBy);
    return rows.map(_trackFromRow).toList();
  }

  static Future<List<LibraryAlbum>> allAlbums() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT albums.id, albums.name, albums.artist, albums.artwork_path, albums.release_year,
             COUNT(tracks.id) as track_count, MAX(tracks.date_added) as date_added
      FROM albums
      LEFT JOIN tracks ON tracks.album_id = albums.id
      GROUP BY albums.id
      HAVING track_count > 0
      ORDER BY albums.artist, albums.name
    ''');
    return rows
        .map((r) => LibraryAlbum(
              id: r['id'] as int,
              name: r['name'] as String,
              artist: r['artist'] as String,
              artworkPath: r['artwork_path'] as String?,
              releaseYear: r['release_year'] as int?,
              trackCount: r['track_count'] as int? ?? 0,
              // MAX(date_added) is the most recent track added to this
              // album — a fair proxy for "when this album was added",
              // since the album row itself has no date_added of its own.
              dateAdded: r['date_added'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(r['date_added'] as int)
                  : DateTime.fromMillisecondsSinceEpoch(0),
            ))
        .toList();
  }

  static Future<List<LibraryTrack>> tracksForAlbum(int albumId) async {
    final db = await instance;
    final rows = await db.query('tracks',
        where: 'album_id = ?', whereArgs: [albumId], orderBy: 'disc_number, track_number');
    return rows.map(_trackFromRow).toList();
  }

  static Future<List<LibraryTrack>> mostPlayed({int limit = 50}) async {
    final db = await instance;
    final rows = await db.query('tracks',
        where: 'play_count > 0 AND $_excludeYoutubeStreams', orderBy: 'play_count DESC', limit: limit);
    return rows.map(_trackFromRow).toList();
  }

  static Future<List<LibraryTrack>> recentlyPlayed({int limit = 50}) async {
    final db = await instance;
    final rows = await db.query('tracks',
        where: 'last_played_at IS NOT NULL AND $_excludeYoutubeStreams',
        orderBy: 'last_played_at DESC',
        limit: limit);
    return rows.map(_trackFromRow).toList();
  }

  static Future<List<LibraryTrack>> favorites() async {
    final db = await instance;
    final rows = await db.query('tracks',
        where: 'is_favorite = 1 AND $_excludeYoutubeStreams', orderBy: 'artist, album, track_number');
    return rows.map(_trackFromRow).toList();
  }

  static Future<void> recordPlay(int trackId) async {
    final db = await instance;
    await db.rawUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, trackId],
    );
  }

  static Future<void> setFavorite(int trackId, bool favorite) async {
    final db = await instance;
    await db.update('tracks', {'is_favorite': favorite ? 1 : 0}, where: 'id = ?', whereArgs: [trackId]);
  }

  static Future<void> setLyrics(int trackId, String lyrics) async {
    final db = await instance;
    await db.update('tracks', {'lyrics': lyrics}, where: 'id = ?', whereArgs: [trackId]);
  }

  static Future<List<Playlist>> allPlaylists() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT playlists.id, playlists.name, playlists.created_at,
             COUNT(playlist_tracks.track_id) as track_count
      FROM playlists
      LEFT JOIN playlist_tracks ON playlist_tracks.playlist_id = playlists.id
      GROUP BY playlists.id
      ORDER BY playlists.created_at DESC
    ''');
    return rows
        .map((r) => Playlist(
              id: r['id'] as int,
              name: r['name'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              trackCount: r['track_count'] as int? ?? 0,
            ))
        .toList();
  }

  static Future<int> createPlaylist(String name) async {
    final db = await instance;
    return db.insert('playlists', {'name': name, 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  static Future<void> deletePlaylist(int playlistId) async {
    final db = await instance;
    await db.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  static Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    final db = await instance;
    final existing = await db.query('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
    await db.insert(
      'playlist_tracks',
      {'playlist_id': playlistId, 'track_id': trackId, 'position': existing.length},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    final db = await instance;
    await db.delete('playlist_tracks',
        where: 'playlist_id = ? AND track_id = ?', whereArgs: [playlistId, trackId]);
  }

  /// Every playlist a track currently belongs to — used when a streamed
  /// YouTube track is downloaded and needs to be swapped in for the new
  /// local-file row wherever the old one was.
  static Future<List<int>> playlistIdsForTrack(int trackId) async {
    final db = await instance;
    final rows = await db.query('playlist_tracks', columns: ['playlist_id'], where: 'track_id = ?', whereArgs: [trackId]);
    return rows.map((r) => r['playlist_id'] as int).toList();
  }

  /// Looks tracks up by id with no `_excludeYoutubeStreams` filter — unlike
  /// every other browse query, restoring a saved queue/session needs to find
  /// a YouTube track too if that's what was last playing.
  static Future<List<LibraryTrack>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await instance;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query('tracks', where: 'id IN ($placeholders)', whereArgs: ids);
    return rows.map(_trackFromRow).toList();
  }

  static Future<List<LibraryTrack>> tracksForPlaylist(int playlistId) async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT tracks.* FROM tracks
      JOIN playlist_tracks ON playlist_tracks.track_id = tracks.id
      WHERE playlist_tracks.playlist_id = ?
      ORDER BY playlist_tracks.position
    ''', [playlistId]);
    return rows.map(_trackFromRow).toList();
  }

  static Future<List<LibraryTrack>> search(String query) async {
    final db = await instance;
    final q = '%$query%';
    final rows = await db.query(
      'tracks',
      where: '(title LIKE ? OR artist LIKE ? OR album LIKE ?) AND $_excludeYoutubeStreams',
      whereArgs: [q, q, q],
      orderBy: 'artist, album, track_number',
    );
    return rows.map(_trackFromRow).toList();
  }

  static Future<List<String>> scannedFolders() async {
    final db = await instance;
    final rows = await db.query('scanned_folders');
    return rows.map((r) => r['path'] as String).toList();
  }

  static Future<void> addScannedFolder(String path) async {
    final db = await instance;
    await db.insert('scanned_folders', {'path': path}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> removeScannedFolder(String path) async {
    final db = await instance;
    await db.delete('scanned_folders', where: 'path = ?', whereArgs: [path]);
  }

  static Future<List<RadioStation>> allRadioStations() async {
    final db = await instance;
    final rows = await db.query('radio_stations', orderBy: 'created_at DESC');
    return rows
        .map((r) => RadioStation(
              id: r['id'] as int,
              name: r['name'] as String,
              url: r['url'] as String,
              type: RadioStationType.fromDb(r['type'] as String? ?? 'audio'),
              logoUrl: r['logo_url'] as String?,
            ))
        .toList();
  }

  static Future<int> addRadioStation(String name, String url, RadioStationType type, {String? logoUrl}) async {
    final db = await instance;
    return db.insert('radio_stations', {
      'name': name,
      'url': url,
      'type': type.toDb(),
      'logo_url': logoUrl,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> deleteRadioStation(int id) async {
    final db = await instance;
    await db.delete('radio_stations', where: 'id = ?', whereArgs: [id]);
  }
}
