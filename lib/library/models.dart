/// A single local audio file and its extracted metadata.
class LibraryTrack {
  final int id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final int? albumId;
  final int trackNumber;
  final int discNumber;
  final Duration duration;
  final String? artworkPath;
  final String? lyrics;
  final String? genre;
  final int playCount;
  final DateTime? lastPlayedAt;
  final bool isFavorite;
  final DateTime dateAdded;

  /// Set only for a track imported from a YouTube Music playlist link. Null
  /// for every normal locally-scanned file.
  final String? youtubeVideoId;

  const LibraryTrack({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.trackNumber,
    required this.discNumber,
    required this.duration,
    required this.artworkPath,
    required this.lyrics,
    required this.genre,
    required this.playCount,
    required this.lastPlayedAt,
    required this.isFavorite,
    required this.dateAdded,
    this.youtubeVideoId,
  });

  /// True for a YouTube-imported track — its `path` is a `youtube:<id>`
  /// placeholder, not a real local file, so playing it always means
  /// streaming (needs internet) instead of reading disk.
  bool get isYoutubeStream => youtubeVideoId != null && path.startsWith('youtube:');

  LibraryTrack copyWith({
    String? path,
    String? title,
    String? artist,
    String? album,
    int? albumId,
    int? trackNumber,
    String? genre,
    int? playCount,
    DateTime? lastPlayedAt,
    bool? isFavorite,
    String? lyrics,
    String? artworkPath,
  }) {
    return LibraryTrack(
      id: id,
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber,
      duration: duration,
      artworkPath: artworkPath ?? this.artworkPath,
      lyrics: lyrics ?? this.lyrics,
      genre: genre ?? this.genre,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      dateAdded: dateAdded,
      youtubeVideoId: youtubeVideoId,
    );
  }
}

class LibraryAlbum {
  final int id;
  final String name;
  final String artist;
  final String? artworkPath;
  final int? releaseYear;
  final int trackCount;
  final DateTime dateAdded;

  const LibraryAlbum({
    required this.id,
    required this.name,
    required this.artist,
    required this.artworkPath,
    required this.releaseYear,
    required this.trackCount,
    required this.dateAdded,
  });
}

/// Whether a saved [RadioStation] is a direct audio stream URL (played
/// in-app via just_audio, like a normal radio station) or a web link (a
/// YouTube video/live stream or other page, opened in an embedded web
/// player instead).
enum RadioStationType {
  audio,
  web;

  static RadioStationType fromDb(String value) => value == 'web' ? RadioStationType.web : RadioStationType.audio;
  String toDb() => name;
}

/// A saved internet radio station or web link: a name, a URL, and which of
/// the two it is.
class RadioStation {
  final int id;
  final String name;
  final String url;
  final RadioStationType type;
  final String? logoUrl;

  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    this.type = RadioStationType.audio,
    this.logoUrl,
  });
}

class Playlist {
  final int id;
  final String name;
  final DateTime createdAt;
  final int trackCount;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.trackCount,
  });
}
