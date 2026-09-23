import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/palettes.dart';
import '../audio/local_playback.dart';
import '../library/artist_photo_service.dart';
import '../library/db.dart';
import '../library/models.dart';
import '../library/scanner.dart';
import '../library/lyrics_service.dart';
import '../library/youtube_service.dart';

export '../library/models.dart';

/// Central app state: theme, local music library, queue, and playback
/// controls. All music is local — nothing here talks to Spotify or any
/// streaming service. Lyrics and artist photos are the two features that
/// may reach the network: lyrics only as a fallback when a track has none
/// embedded, artist photos automatically in the background after a scan
/// finds a new artist (see [_syncArtistPhotos]).
class AppState extends ChangeNotifier {
  static const _themePrefKey = 'cartoon_music.theme';

  CartoonPalette _palette = CartoonPalette.sunny;
  CartoonPalette get palette => _palette;

  CustomThemeConfig customTheme = const CustomThemeConfig();

  final LocalPlayback playback;

  /// Lets AppState show a SnackBar (e.g. "skipped a YouTube track") without
  /// needing a BuildContext of its own. Null in tests/headless use — every
  /// call site guards for that.
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  List<LibraryAlbum> albums = [];
  List<LibraryTrack> allTracks = [];

  /// Artist name -> local cached photo path, filled in by
  /// [_syncArtistPhotos]. Read via [artistPhoto].
  Map<String, String> artistPhotos = {};
  List<Playlist> playlists = [];
  List<RadioStation> radioStations = [];
  RadioStation? currentRadioStation;
  bool radioReconnecting = false;
  List<String> scannedFolders = [];
  bool isScanning = false;
  int scanProgress = 0;
  bool libraryLoaded = false;

  bool importingYoutubePlaylist = false;
  bool downloadingYoutubePlaylist = false;
  int youtubePlaylistDownloadProgress = 0;
  int youtubePlaylistDownloadTotal = 0;
  Set<int> downloadingYoutubeTrackIds = {};

  /// Where YouTube downloads are saved: a "YouTube Downloads" subfolder
  /// inside the first scanned library folder, so a rescan (or the
  /// auto-refresh after downloading) picks them up like any other file.
  /// Null if no library folder has been added yet — downloads need
  /// somewhere a scan will actually find.
  String? get youtubeDownloadFolder =>
      scannedFolders.isEmpty ? null : p.join(scannedFolders.first, 'YouTube Downloads');

  List<LibraryTrack> queue = [];
  int queueIndex = -1;
  LibraryTrack? get currentTrack => queueIndex >= 0 && queueIndex < queue.length ? queue[queueIndex] : null;

  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool shuffle = false;
  bool repeat = false;
  double volume = 0.8;

  ParsedLyrics currentLyrics = ParsedLyrics.empty;
  bool loadingLyrics = false;

  AppState({LocalPlayback? playback, this.scaffoldMessengerKey}) : playback = playback ?? LocalPlayback() {
    _loadTheme();
    _loadCustomTheme();
    _init();
    this.playback.onTick = (tick) {
      isPlaying = tick.isPlaying;
      position = tick.position;
      duration = tick.duration;
      notifyListeners();
    };
    this.playback.onTrackComplete = () {
      // Must read currentTrack (and fire this) before skipNext() advances
      // queueIndex, since that's the track that just finished playing.
      unawaited(_recordCompletedPlay());
      skipNext();
    };
    this.playback.onNextRequested = () {
      skipNext();
    };
    this.playback.onPlaybackError = () {
      // Mid-playback failure on a queue track (corrupt frame, underrun, a
      // file on a flaky drive) — recover the same way the user's manual
      // "next" does, rather than leaving playback silently stuck.
      skipNext();
    };
    this.playback.onPreviousRequested = () {
      skipPrevious();
    };
    this.playback.onStreamReconnecting = (reconnecting) {
      radioReconnecting = reconnecting;
      notifyListeners();
    };
  }

  Future<void> _init() async {
    scannedFolders = await LibraryDatabase.scannedFolders();
    await refreshLibrary();
    await _restoreVolume();
    await _restorePlaybackState();
  }

  Future<void> refreshLibrary() async {
    albums = await LibraryDatabase.allAlbums();
    allTracks = await LibraryDatabase.allTracks();
    playlists = await LibraryDatabase.allPlaylists();
    radioStations = await LibraryDatabase.allRadioStations();
    libraryLoaded = true;
    notifyListeners();
    // Fire-and-forget: don't block library load on network lookups. Any
    // artist already in `artistPhotos` (from a previous sync this session)
    // or already cached on disk is skipped, so this only ever does network
    // work for an artist that's genuinely new to the library.
    unawaited(_syncArtistPhotos());
  }

  String? artistPhoto(String artist) => artistPhotos[artist];

  Future<void> _syncArtistPhotos() async {
    final names = albums.map((a) => a.artist).toSet();
    for (final name in names) {
      if (artistPhotos.containsKey(name)) continue;
      final photo = await ArtistPhotoService.photoFor(name);
      if (photo == null) continue;
      artistPhotos[name] = photo;
      notifyListeners();
    }
  }

  /// Display helpers so the transport bar / mini player / Now Playing can
  /// show either a local track or a live radio station without needing to
  /// know which one is actually playing.
  bool get hasNowPlaying => currentTrack != null || currentRadioStation != null;
  String get nowPlayingTitle => currentTrack?.title ?? currentRadioStation?.name ?? 'Nothing playing';
  String get nowPlayingSubtitle => currentTrack?.artist ??
      (currentRadioStation != null ? (radioReconnecting ? 'Reconnecting...' : 'Live Radio') : '');

  Future<void> addRadioStation(String name, String url, {RadioStationType type = RadioStationType.audio, String? logoUrl}) async {
    await LibraryDatabase.addRadioStation(name, url, type, logoUrl: logoUrl);
    radioStations = await LibraryDatabase.allRadioStations();
    notifyListeners();
  }

  Future<void> deleteRadioStation(int id) async {
    await LibraryDatabase.deleteRadioStation(id);
    radioStations = await LibraryDatabase.allRadioStations();
    notifyListeners();
  }

  /// Plays a saved radio station. Stops whatever local queue was playing —
  /// a live stream isn't part of the queue and has no fixed duration, so it
  /// doesn't make sense to keep queue/shuffle/repeat state active.
  Future<void> playRadioStation(RadioStation station) async {
    queue = [];
    queueIndex = -1;
    currentRadioStation = station;
    radioReconnecting = false;
    currentLyrics = ParsedLyrics.empty;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();
    try {
      await playback.playUrl(station.url, title: station.name, artist: 'Live Radio');
    } catch (e) {
      // Not every URL a user adds as an "audio stream" actually is one (a
      // plain webpage, for instance) — leaving currentRadioStation set here
      // would show a station that isn't really playing. Let the caller show
      // an error / offer the web-player fallback instead.
      currentRadioStation = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addFolderAndScan(String folderPath) async {
    isScanning = true;
    scanProgress = 0;
    notifyListeners();
    await LibraryScanner.scanFolder(folderPath, onProgress: (count) {
      scanProgress = count;
      notifyListeners();
    });
    scannedFolders = await LibraryDatabase.scannedFolders();
    isScanning = false;
    await refreshLibrary();
  }

  Future<void> rescanAllFolders() async {
    isScanning = true;
    notifyListeners();
    for (final folder in scannedFolders) {
      await LibraryScanner.scanFolder(folder, onProgress: (count) {
        scanProgress = count;
        notifyListeners();
      });
    }
    isScanning = false;
    await refreshLibrary();
  }

  Future<void> removeFolder(String folderPath) async {
    await LibraryDatabase.removeScannedFolder(folderPath);
    scannedFolders = await LibraryDatabase.scannedFolders();
    notifyListeners();
  }

  Future<List<LibraryTrack>> tracksForAlbum(int albumId) => LibraryDatabase.tracksForAlbum(albumId);

  /// Plays an album straight from the Albums grid, without navigating into
  /// its detail screen first.
  Future<void> playAlbum(LibraryAlbum album) async {
    final tracks = await LibraryDatabase.tracksForAlbum(album.id);
    if (tracks.isEmpty) return;
    await playTrack(tracks.first, contextQueue: tracks);
  }

  Future<List<LibraryTrack>> mostPlayed() => LibraryDatabase.mostPlayed();
  Future<List<LibraryTrack>> recentlyPlayed() => LibraryDatabase.recentlyPlayed();
  Future<List<LibraryTrack>> favorites() => LibraryDatabase.favorites();
  Future<List<LibraryTrack>> searchTracks(String query) => LibraryDatabase.search(query);
  Future<List<LibraryTrack>> tracksForPlaylist(int playlistId) => LibraryDatabase.tracksForPlaylist(playlistId);

  Future<void> toggleFavorite(LibraryTrack track) async {
    final newValue = !track.isFavorite;
    await LibraryDatabase.setFavorite(track.id, newValue);
    _replaceTrackEverywhere(track.copyWith(isFavorite: newValue));
    notifyListeners();
  }

  void _replaceTrackEverywhere(LibraryTrack updated) {
    allTracks = allTracks.map((t) => t.id == updated.id ? updated : t).toList();
    queue = queue.map((t) => t.id == updated.id ? updated : t).toList();
  }

  /// Saves edited metadata (title/artist/album/track number/genre/year) for
  /// a track, then refreshes the album grid (a renamed album may merge into
  /// or split off from another one).
  Future<void> updateTrackMetadata(
    LibraryTrack track, {
    required String title,
    required String artist,
    required String album,
    required int trackNumber,
    String? genre,
    int? releaseYear,
    String? artworkPath,
  }) async {
    await LibraryDatabase.updateTrackMetadata(
      track.id,
      title: title,
      artist: artist,
      album: album,
      trackNumber: trackNumber,
      genre: genre,
      releaseYear: releaseYear,
      artworkPath: artworkPath,
    );
    // A YouTube-streamed track has no real file at `path` to tag — only its
    // library row can be edited.
    if (!track.isYoutubeStream) {
      _writeMetadataToFile(
        track.path,
        title: title,
        artist: artist,
        album: album,
        trackNumber: trackNumber,
        genre: genre,
        releaseYear: releaseYear,
        artworkPath: artworkPath,
      );
    }
    await refreshLibrary();
    final updated = allTracks.firstWhere((t) => t.id == track.id, orElse: () => track);
    queue = queue.map((t) => t.id == updated.id ? updated : t).toList();
    notifyListeners();
  }

  /// Writes edited metadata into the actual audio file's tags, so a save in
  /// the Edit Song screen changes the file itself and not just this app's
  /// library — matches what a user reasonably expects "editing a song" to
  /// do. Best-effort: an unsupported container or an unwritable file just
  /// leaves the file's tags as they were, since the library row (the part
  /// the UI actually shows) is already saved either way.
  void _writeMetadataToFile(
    String path, {
    required String title,
    required String artist,
    required String album,
    required int trackNumber,
    String? genre,
    int? releaseYear,
    String? artworkPath,
  }) {
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      updateMetadata(file, (metadata) {
        metadata.setTitle(title);
        metadata.setArtist(artist);
        metadata.setAlbum(album);
        if (trackNumber > 0) metadata.setTrackNumber(trackNumber);
        if (genre != null) metadata.setGenres([genre]);
        if (releaseYear != null) metadata.setYear(DateTime(releaseYear));
        if (artworkPath != null) {
          final artFile = File(artworkPath);
          if (artFile.existsSync()) {
            final mimetype = p.extension(artworkPath).toLowerCase() == '.png' ? 'image/png' : 'image/jpeg';
            metadata.setPictures([Picture(artFile.readAsBytesSync(), mimetype, PictureType.coverFront)]);
          }
        }
      });
    } catch (_) {
      // See doc comment: a failed tag write shouldn't block the save.
    }
  }

  /// Removes a track: stops playback if it's the current track (removing it
  /// from the queue) and drops its DB row. When [deleteFile] is true, also
  /// deletes the actual audio file from disk — irreversible, so callers must
  /// confirm with the user first (and let them choose which of the two they
  /// want, via the prompt in `confirmDeleteTrack`).
  Future<void> deleteTrack(LibraryTrack track, {required bool deleteFile}) async {
    final wasCurrent = currentTrack?.id == track.id;
    final removedIndex = queue.indexWhere((t) => t.id == track.id);
    if (removedIndex >= 0) {
      queue = List<LibraryTrack>.from(queue)..removeAt(removedIndex);
      if (removedIndex < queueIndex) {
        queueIndex--;
      } else if (removedIndex == queueIndex) {
        queueIndex = queue.isEmpty ? -1 : queueIndex.clamp(0, queue.length - 1);
      }
    }
    if (wasCurrent) {
      if (queue.isEmpty) {
        await playback.stop();
      } else {
        await _playCurrent();
      }
    }

    await LibraryDatabase.deleteTrack(track.id);
    if (deleteFile) {
      try {
        final file = File(track.path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // File may already be gone or unwritable — the library row is still
        // removed either way, which is the part the user is actually after.
      }
    }
    await refreshLibrary();
    notifyListeners();
  }

  /// Removes every track in an album, same as calling [deleteTrack] on each
  /// one — the album's own row disappears on its own once its last track is
  /// gone (see `LibraryDatabase.deleteTrack`). Irreversible when
  /// [deleteFiles] is true, so callers must confirm with the user first.
  Future<void> deleteAlbum(LibraryAlbum album, {required bool deleteFiles}) async {
    final tracks = await LibraryDatabase.tracksForAlbum(album.id);
    for (final track in tracks) {
      await deleteTrack(track, deleteFile: deleteFiles);
    }
  }

  Future<int> createPlaylist(String name) async {
    final id = await LibraryDatabase.createPlaylist(name);
    playlists = await LibraryDatabase.allPlaylists();
    notifyListeners();
    return id;
  }

  Future<void> deletePlaylist(int playlistId) async {
    await LibraryDatabase.deletePlaylist(playlistId);
    playlists = await LibraryDatabase.allPlaylists();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(int playlistId, LibraryTrack track) async {
    await LibraryDatabase.addTrackToPlaylist(playlistId, track.id);
    playlists = await LibraryDatabase.allPlaylists();
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist(int playlistId, LibraryTrack track) async {
    await LibraryDatabase.removeTrackFromPlaylist(playlistId, track.id);
    playlists = await LibraryDatabase.allPlaylists();
    notifyListeners();
  }

  /// Plays a YouTube Music/YouTube link right away. A playlist *or album*
  /// link (both are just playlists under the hood — an album is a
  /// `list=OLAK5uy_...` playlist id, which [YoutubeService.extractPlaylistId]
  /// already matches generically) imports the whole thing as a real, saved
  /// Playah playlist, same as before. A plain song link (`watch?v=`,
  /// `youtu.be/...`) plays just that one track without creating a playlist
  /// for it. Tracks are stored as ordinary `tracks` rows (see
  /// `LibraryDatabase.upsertYoutubeTrack`) so they're remembered across
  /// restarts like any other, though they only ever stream — playing again
  /// later needs an internet connection every time to resolve a fresh
  /// stream URL. Returns the played item's name and track count (1 for a
  /// single song) for a confirmation message. Throws on a bad link or
  /// nothing playable.
  Future<({String name, int trackCount})> importYoutubeLink(String url) async {
    final playlistId = YoutubeService.extractPlaylistId(url);
    if (playlistId != null) return _importYoutubePlaylist(playlistId);

    final videoId = YoutubeService.extractVideoId(url);
    if (videoId == null) {
      throw const FormatException("That doesn't look like a YouTube song, album, or playlist link.");
    }
    return _importYoutubeVideo(videoId);
  }

  Future<({String name, int trackCount})> _importYoutubePlaylist(String playlistId) async {
    importingYoutubePlaylist = true;
    notifyListeners();
    try {
      final playlist = await YoutubeService.fetchPlaylist(playlistId);
      final ytTracks = playlist.tracks;
      if (ytTracks.isEmpty) {
        throw Exception("Couldn't find any playable tracks in that playlist.");
      }

      final playlistName = playlist.title ?? 'YouTube Playlist';
      final playlistDbId = await LibraryDatabase.createPlaylist(playlistName);
      for (var i = 0; i < ytTracks.length; i++) {
        final t = ytTracks[i];
        final trackId = await LibraryDatabase.upsertYoutubeTrack(
          videoId: t.videoId,
          title: t.title,
          artist: t.artist,
          album: playlistName,
          trackNumber: i + 1,
          duration: t.duration,
        );
        await LibraryDatabase.addTrackToPlaylist(playlistDbId, trackId);
      }

      await refreshLibrary();
      final tracks = await LibraryDatabase.tracksForPlaylist(playlistDbId);

      currentRadioStation = null;
      radioReconnecting = false;
      queue = shuffle ? _shuffled(tracks) : tracks;
      queueIndex = 0;
      notifyListeners();
      await _playCurrent();

      unawaited(_cacheYoutubeThumbnails(tracks, ytTracks));

      return (name: playlistName, trackCount: tracks.length);
    } finally {
      importingYoutubePlaylist = false;
      notifyListeners();
    }
  }

  Future<({String name, int trackCount})> _importYoutubeVideo(String videoId) async {
    importingYoutubePlaylist = true;
    notifyListeners();
    try {
      final info = await YoutubeService.fetchVideoInfo(videoId);
      final trackId = await LibraryDatabase.upsertYoutubeTrack(
        videoId: videoId,
        title: info.title,
        artist: info.artist,
        album: 'YouTube',
        trackNumber: 1,
        duration: info.duration,
      );

      await refreshLibrary();
      final tracks = await LibraryDatabase.tracksByIds([trackId]);
      if (tracks.isEmpty) throw Exception("Couldn't load that video.");
      final track = tracks.first;

      currentRadioStation = null;
      radioReconnecting = false;
      queue = [track];
      queueIndex = 0;
      notifyListeners();
      await _playCurrent();

      unawaited(_cacheYoutubeThumbnails([track], [
        YoutubePlaylistTrack(
          videoId: videoId,
          title: info.title,
          artist: info.artist,
          duration: info.duration,
          thumbnailUrl: info.thumbnailUrl,
        ),
      ]));

      return (name: info.title, trackCount: 1);
    } finally {
      importingYoutubePlaylist = false;
      notifyListeners();
    }
  }

  /// Starts [downloadFromYoutubeLink] without making the caller wait for
  /// it — the result (or error) is reported later as a SnackBar via
  /// [scaffoldMessengerKey] instead of through the returned Future, so the
  /// screen that kicked this off doesn't need to stay open, or block
  /// interaction elsewhere in the app, while a big playlist/album downloads.
  /// [downloadingYoutubePlaylist]/[youtubePlaylistDownloadProgress]/
  /// [youtubePlaylistDownloadTotal] still update live for a background
  /// progress indicator.
  ///
  /// [input] may hold several links (whitespace/newline separated). They join
  /// a queue that downloads one at a time, since the progress state above is
  /// single-instance. Returns how many links were queued.
  int startYoutubeDownload(String input) {
    final urls = input.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (urls.isEmpty) return 0;
    _pendingDownloadUrls.addAll(urls);
    notifyListeners();
    if (!_downloadRunnerActive) unawaited(_drainDownloadQueue());
    return urls.length;
  }

  final List<String> _pendingDownloadUrls = [];
  bool _downloadRunnerActive = false;
  int get pendingYoutubeDownloads => _pendingDownloadUrls.length;

  Future<void> _drainDownloadQueue() async {
    _downloadRunnerActive = true;
    try {
      while (_pendingDownloadUrls.isNotEmpty) {
        // A bulk "download queue" run shares the progress state; let it finish.
        while (downloadingYoutubePlaylist) {
          await Future.delayed(const Duration(seconds: 1));
        }
        final url = _pendingDownloadUrls.removeAt(0);
        await _runYoutubeDownloadInBackground(url);
        notifyListeners();
      }
    } finally {
      _downloadRunnerActive = false;
    }
  }

  Future<void> _runYoutubeDownloadInBackground(String url) async {
    final messenger = scaffoldMessengerKey?.currentState;
    try {
      final result = await downloadFromYoutubeLink(url);
      final message = result.trackCount == 1
          ? 'Downloaded "${result.name}" to your library.'
          : 'Downloaded "${result.name}" (${result.trackCount} tracks) to your library.';
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      final reason = e is FormatException ? e.message : e.toString().replaceFirst('Exception: ', '');
      messenger?.showSnackBar(SnackBar(content: Text("Couldn't download that: $reason")));
    }
  }

  /// Like [importYoutubeLink], but downloads as a permanent local mp3 (via
  /// [YoutubeService.downloadAudio]) instead of just streaming — no
  /// internet needed to play back afterward. A playlist/album link
  /// downloads every track into a new playlist *and* into its own subfolder
  /// (named after the playlist/album) inside [youtubeDownloadFolder],
  /// skipping (rather than aborting on) any track that fails; a plain song
  /// link downloads just that one file straight into [youtubeDownloadFolder]
  /// itself, no subfolder or playlist created. Needs a library folder
  /// already added (see [youtubeDownloadFolder]).
  Future<({String name, int trackCount})> downloadFromYoutubeLink(String url) async {
    final folder = youtubeDownloadFolder;
    if (folder == null) {
      throw Exception('Add a library folder first (in Settings) so downloads have somewhere to land.');
    }
    final playlistId = YoutubeService.extractPlaylistId(url);
    if (playlistId != null) return _downloadYoutubePlaylist(playlistId, folder);

    final videoId = YoutubeService.extractVideoId(url);
    if (videoId == null) {
      throw const FormatException("That doesn't look like a YouTube song, album, or playlist link.");
    }
    return _downloadYoutubeVideo(videoId, folder);
  }

  Future<({String name, int trackCount})> _downloadYoutubePlaylist(String playlistId, String folder) async {
    importingYoutubePlaylist = true;
    // Set immediately (not just after the playlist is fetched) so the
    // background progress indicator appears the moment the download
    // starts, rather than only once track downloading itself begins.
    downloadingYoutubePlaylist = true;
    notifyListeners();
    try {
      final playlist = await YoutubeService.fetchPlaylist(playlistId);
      final ytTracks = playlist.tracks;
      if (ytTracks.isEmpty) {
        throw Exception("Couldn't find any playable tracks in that playlist.");
      }

      final playlistName = playlist.title ?? 'YouTube Playlist';
      final playlistDbId = await LibraryDatabase.createPlaylist(playlistName);
      // A playlist or album download gets its own subfolder named after it
      // (unlike a single-song download, which lands directly in [folder])
      // so downloads from different playlists/albums don't end up mixed
      // together in one flat directory.
      final playlistFolder = p.join(folder, YoutubeService.sanitizeFolderName(playlistName));

      youtubePlaylistDownloadTotal = ytTracks.length;
      youtubePlaylistDownloadProgress = 0;
      notifyListeners();

      var downloaded = 0;
      for (final t in ytTracks) {
        try {
          // Already downloaded (this video, from an earlier playlist/track
          // download) — reuse that file instead of fetching it again.
          final existingId = await LibraryDatabase.downloadedTrackIdForYoutubeVideo(t.videoId);
          final trackId = existingId ??
              await LibraryScanner.importSingleFile(
                File(await YoutubeService.downloadAudio(t.videoId, playlistFolder)),
                youtubeVideoId: t.videoId,
              );
          await LibraryDatabase.addTrackToPlaylist(playlistDbId, trackId);
          downloaded++;
        } catch (_) {
          // Skip a track that fails (CDN hiccup, deleted video) rather than
          // aborting the rest of the playlist.
        }
        youtubePlaylistDownloadProgress++;
        notifyListeners();
      }

      if (downloaded == 0) {
        await LibraryDatabase.deletePlaylist(playlistDbId);
        throw Exception("Couldn't download any tracks from that playlist.");
      }

      await refreshLibrary();
      playlists = await LibraryDatabase.allPlaylists();
      notifyListeners();
      return (name: playlistName, trackCount: downloaded);
    } finally {
      importingYoutubePlaylist = false;
      downloadingYoutubePlaylist = false;
      notifyListeners();
    }
  }

  Future<({String name, int trackCount})> _downloadYoutubeVideo(String videoId, String folder) async {
    importingYoutubePlaylist = true;
    downloadingYoutubePlaylist = true;
    youtubePlaylistDownloadTotal = 1;
    youtubePlaylistDownloadProgress = 0;
    notifyListeners();
    try {
      // Already downloaded elsewhere — no need to fetch it again.
      final existingId = await LibraryDatabase.downloadedTrackIdForYoutubeVideo(videoId);
      final trackId = existingId ??
          await LibraryScanner.importSingleFile(
            File(await YoutubeService.downloadAudio(videoId, folder)),
            youtubeVideoId: videoId,
          );
      await refreshLibrary();
      youtubePlaylistDownloadProgress = 1;
      final tracks = await LibraryDatabase.tracksByIds([trackId]);
      return (name: tracks.isEmpty ? 'the track' : tracks.first.title, trackCount: 1);
    } finally {
      importingYoutubePlaylist = false;
      downloadingYoutubePlaylist = false;
      notifyListeners();
    }
  }

  /// Converts a single already-streamed YouTube track (see
  /// [LibraryTrack.isYoutubeStream]) into a permanent local mp3, swapping it
  /// in wherever the streamed row was referenced (queue, playlists) so it
  /// plays from disk — no internet needed — from now on. The original
  /// streamed row is removed.
  Future<void> downloadYoutubeTrack(LibraryTrack track) async {
    final folder = youtubeDownloadFolder;
    if (folder == null) {
      throw Exception('Add a library folder first (in Settings) so downloads have somewhere to land.');
    }
    final videoId = track.youtubeVideoId;
    if (videoId == null || !track.isYoutubeStream) return;

    downloadingYoutubeTrackIds = {...downloadingYoutubeTrackIds, track.id};
    notifyListeners();
    try {
      // Already downloaded under a different playlist/import — reuse that
      // file instead of fetching this video again.
      final existingId = await LibraryDatabase.downloadedTrackIdForYoutubeVideo(videoId);
      final newTrackId = existingId ??
          await LibraryScanner.importSingleFile(
            File(await YoutubeService.downloadAudio(videoId, folder)),
            youtubeVideoId: videoId,
          );

      final playlistIds = await LibraryDatabase.playlistIdsForTrack(track.id);
      for (final playlistId in playlistIds) {
        await LibraryDatabase.addTrackToPlaylist(playlistId, newTrackId);
      }
      await LibraryDatabase.deleteTrack(track.id);

      await refreshLibrary();
      final updatedRows = await LibraryDatabase.tracksByIds([newTrackId]);
      final updated = updatedRows.isEmpty ? null : updatedRows.first;
      queue = updated != null
          ? queue.map((t) => t.id == track.id ? updated : t).toList()
          : queue.where((t) => t.id != track.id).toList();
      playlists = await LibraryDatabase.allPlaylists();
      notifyListeners();
    } finally {
      downloadingYoutubeTrackIds = {...downloadingYoutubeTrackIds}..remove(track.id);
      notifyListeners();
    }
  }

  /// Starts [_downloadAllYoutubeTracks] without making the caller wait for
  /// it — same fire-and-forget pattern as [startYoutubeDownload], reporting
  /// progress via the floating indicator and the result as a SnackBar
  /// instead of through the returned Future.
  void startBulkYoutubeDownload(List<LibraryTrack> tracks) {
    unawaited(_downloadAllYoutubeTracks(tracks));
  }

  /// Downloads every still-streamed ([LibraryTrack.isYoutubeStream]) track
  /// in [tracks] — e.g. a whole playlist's worth — as permanent local mp3s,
  /// skipping any that fail (CDN hiccup, deleted video) rather than
  /// aborting the rest. Each track goes through [downloadYoutubeTrack],
  /// which already reuses an existing local copy instead of re-downloading
  /// one, so tracks already downloaded elsewhere cost nothing here.
  Future<void> _downloadAllYoutubeTracks(List<LibraryTrack> tracks) async {
    final messenger = scaffoldMessengerKey?.currentState;
    final toDownload = tracks.where((t) => t.isYoutubeStream).toList();
    if (toDownload.isEmpty) return;

    if (youtubeDownloadFolder == null) {
      messenger?.showSnackBar(const SnackBar(
        content: Text('Add a library folder first (in Settings) so downloads have somewhere to land.'),
      ));
      return;
    }

    downloadingYoutubePlaylist = true;
    youtubePlaylistDownloadTotal = toDownload.length;
    youtubePlaylistDownloadProgress = 0;
    notifyListeners();

    var succeeded = 0;
    try {
      for (final track in toDownload) {
        try {
          await downloadYoutubeTrack(track);
          succeeded++;
        } catch (_) {
          // Skip a track that fails rather than aborting the rest.
        }
        youtubePlaylistDownloadProgress++;
        notifyListeners();
      }
      final message = succeeded == toDownload.length
          ? 'Downloaded $succeeded ${succeeded == 1 ? 'track' : 'tracks'} to your library.'
          : 'Downloaded $succeeded of ${toDownload.length} tracks to your library.';
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      downloadingYoutubePlaylist = false;
      notifyListeners();
    }
  }

  /// Fetches and saves each imported track's thumbnail in the background
  /// (after playback has already started, so a big playlist doesn't delay
  /// it) then pushes the resulting artwork into `allTracks`/`queue` so it
  /// shows up without the user needing to navigate away and back.
  Future<void> _cacheYoutubeThumbnails(List<LibraryTrack> tracks, List<YoutubePlaylistTrack> ytTracks) async {
    for (var i = 0; i < tracks.length && i < ytTracks.length; i++) {
      final track = tracks[i];
      final yt = ytTracks[i];
      final artworkPath = await YoutubeService.cacheThumbnail(yt.videoId, yt.thumbnailUrl, yt.artist);
      if (artworkPath == null) continue;
      await LibraryDatabase.setTrackArtwork(track.id, artworkPath);
      _replaceTrackEverywhere(track.copyWith(artworkPath: artworkPath));
      notifyListeners();
    }
  }

  Future<void> playTrack(LibraryTrack track, {List<LibraryTrack>? contextQueue}) async {
    currentRadioStation = null;
    radioReconnecting = false;
    final baseQueue = contextQueue ?? [track];
    queue = shuffle ? _shuffled(baseQueue, keepFirst: track) : baseQueue;
    queueIndex = queue.indexWhere((t) => t.id == track.id);
    if (queueIndex < 0) queueIndex = 0;
    notifyListeners();
    await _playCurrent();
  }

  /// Insert a track to play right after the current one, without disturbing
  /// the rest of the queue.
  void playNext(LibraryTrack track) {
    if (queue.isEmpty) {
      playTrack(track);
      return;
    }
    queue.insert(queueIndex + 1, track);
    notifyListeners();
    _savePlaybackState();
  }

  /// Append a track to the end of the queue.
  void addToQueue(LibraryTrack track) {
    if (queue.isEmpty) {
      playTrack(track);
      return;
    }
    queue.add(track);
    notifyListeners();
    _savePlaybackState();
  }

  /// Move a queue item from [oldIndex] to [newIndex] (drag-to-reorder).
  /// Tracks the currently-playing track by identity so it keeps playing
  /// uninterrupted even if its position in the list changes.
  void reorderQueue(int oldIndex, int newIndex) {
    final currentId = currentTrack?.id;
    final track = queue.removeAt(oldIndex);
    queue.insert(newIndex, track);
    if (currentId != null) {
      queueIndex = queue.indexWhere((t) => t.id == currentId);
    }
    notifyListeners();
    _savePlaybackState();
  }

  /// [attemptsLeft] bounds auto-skip retries when a file fails to load
  /// (moved/deleted/corrupted since the last scan) — defaults to one full
  /// lap of the queue so a fully broken queue stops instead of recursing
  /// forever, rather than the old behavior of playback silently going
  /// quiet and staying stuck on the broken track until the user manually
  /// hit skip.
  Future<void> _playCurrent([int? attemptsLeft]) async {
    final track = currentTrack;
    if (track == null) return;
    final remaining = attemptsLeft ?? queue.length;
    try {
      if (track.isYoutubeStream) {
        await _playYoutubeTrack(track);
      } else {
        // Bounded the same way the YouTube path already is: the underlying
        // just_audio_media_kit backend resolves its load only when a
        // buffering event happens to arrive after the file is marked open,
        // which occasionally races and never arrives — with no timeout that
        // hung the auto-advance forever on a random track with no error, no
        // retry, and no fallback to the next queued song.
        await playback
            .playFile(
              track.path,
              title: track.title,
              artist: track.artist,
              album: track.album,
              artworkPath: track.artworkPath,
              duration: track.duration,
            )
            .timeout(const Duration(seconds: 15));
      }
    } catch (e) {
      // YouTube skips are surfaced (a SnackBar) because they're common
      // enough — YouTube's CDN 403s some requests unpredictably even on a
      // good connection — that a silent skip reads as "songs are randomly
      // missing" rather than "this specific track couldn't load." A broken
      // local file skips silently as before; that's rare enough not to need
      // the same treatment. The underlying error only goes to debugPrint
      // (not the SnackBar) since it's rarely actionable for the user, but
      // swallowing it entirely made every past failure unreproducible.
      if (track.isYoutubeStream) {
        debugPrint('YouTube track "${track.title}" failed to play: $e');
        _notifyYoutubeTrackSkipped(track);
      }
      if (remaining > 1 && _advanceQueueIndex()) {
        notifyListeners();
        await _playCurrent(remaining - 1);
      } else {
        await playback.stop();
      }
      return;
    }
    notifyListeners();
    unawaited(loadLyricsFor(track));
    unawaited(_savePlaybackState());
  }

  /// Resolves and plays a YouTube track, retrying once after a short delay
  /// before giving up. Needs an internet connection every time (these
  /// tracks always stream) — a failure here (offline, video taken down, or
  /// YouTube's CDN 403-ing that particular request, which happens
  /// unpredictably even for a valid signed URL) falls through to the same
  /// auto-skip as a broken local file, after this one retry. Bounded by a
  /// timeout on each attempt: both the resolve call and handing the URL to
  /// the player can hang indefinitely on a bad connection or a stream the
  /// player can't open, instead of erroring — without this, a single bad
  /// track leaves the caller (e.g. the "Loading playlist…" dialog) stuck
  /// forever with no way out.
  Future<void> _playYoutubeTrack(LibraryTrack track, {int attemptsLeft = 2}) async {
    try {
      final stream = await YoutubeService.resolveAudioStream(track.youtubeVideoId!)
          .timeout(const Duration(seconds: 15));
      await playback
          .playRemoteUrl(
            stream.url,
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkPath: track.artworkPath,
            duration: track.duration,
            headers: stream.headers,
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      if (attemptsLeft > 1) {
        await Future.delayed(const Duration(seconds: 2));
        return _playYoutubeTrack(track, attemptsLeft: attemptsLeft - 1);
      }
      rethrow;
    }
  }

  /// Brief SnackBar so a skipped YouTube track is visible instead of the
  /// queue just silently jumping ahead. No-op if there's nowhere to show it
  /// (no messenger attached yet, e.g. during very early startup).
  void _notifyYoutubeTrackSkipped(LibraryTrack track) {
    final messenger = scaffoldMessengerKey?.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text('Skipped "${track.title}" — couldn\'t load from YouTube.')));
  }

  /// Bumps play count/last-played only for a track that reached natural
  /// completion (`ProcessingState.completed`) — not one the user skipped
  /// past partway through, and not just because it started playing.
  Future<void> _recordCompletedPlay() async {
    final track = currentTrack;
    if (track == null) return;
    await LibraryDatabase.recordPlay(track.id);
    _replaceTrackEverywhere(track.copyWith(playCount: track.playCount + 1, lastPlayedAt: DateTime.now()));
    notifyListeners();
  }

  static const _prefQueueIds = 'playback.queueIds';
  static const _prefQueueIndex = 'playback.queueIndex';
  static const _prefShuffle = 'playback.shuffle';
  static const _prefRepeat = 'playback.repeat';
  static const _prefPositionMs = 'playback.positionMs';

  Future<void> _savePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefQueueIds, queue.map((t) => t.id).join(','));
    await prefs.setInt(_prefQueueIndex, queueIndex);
    await prefs.setBool(_prefShuffle, shuffle);
    await prefs.setBool(_prefRepeat, repeat);
    await prefs.setInt(_prefPositionMs, position.inMilliseconds);
  }

  Future<void> _restorePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final idsStr = prefs.getString(_prefQueueIds);
    final savedIndex = prefs.getInt(_prefQueueIndex);
    if (idsStr == null || idsStr.isEmpty || savedIndex == null) return;

    final ids = idsStr.split(',').map(int.parse).toList();
    // Not `allTracks` — that excludes YouTube tracks, but a saved queue can
    // legitimately consist entirely of one of those.
    final restoredTracks = await LibraryDatabase.tracksByIds(ids);
    final byId = {for (final t in restoredTracks) t.id: t};
    final restoredQueue = ids.map((id) => byId[id]).whereType<LibraryTrack>().toList();
    if (restoredQueue.isEmpty) return;

    queue = restoredQueue;
    queueIndex = savedIndex.clamp(0, queue.length - 1);
    shuffle = prefs.getBool(_prefShuffle) ?? false;
    repeat = prefs.getBool(_prefRepeat) ?? false;
    final savedPosition = Duration(milliseconds: prefs.getInt(_prefPositionMs) ?? 0);
    duration = currentTrack?.duration ?? Duration.zero;
    position = savedPosition;
    isPlaying = false;
    notifyListeners();

    // Actually load the file (paused) so play/pause/seek/skip work right
    // away — without this, the track shown on startup can't be played
    // until the user picks something from a list again.
    final track = currentTrack;
    if (track != null) {
      try {
        if (track.isYoutubeStream) {
          final stream = await YoutubeService.resolveAudioStream(track.youtubeVideoId!)
              .timeout(const Duration(seconds: 15));
          await playback
              .loadRemoteUrl(
                stream.url,
                startAt: savedPosition,
                title: track.title,
                artist: track.artist,
                album: track.album,
                artworkPath: track.artworkPath,
                duration: track.duration,
                headers: stream.headers,
              )
              .timeout(const Duration(seconds: 15));
        } else {
          await playback.loadFile(
            track.path,
            startAt: savedPosition,
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkPath: track.artworkPath,
            duration: track.duration,
          );
        }
      } catch (_) {
        // Offline, or the video's since gone — nothing loaded, but the rest
        // of the restored queue/position state is still fine to keep; the
        // user can hit play on something else instead of the app crashing.
      }
    }
  }

  Future<void> togglePlayPause() async {
    if (currentTrack == null && currentRadioStation == null) return;
    final wasPlaying = isPlaying;
    wasPlaying ? await playback.pause() : await playback.resume();
    // isPlaying updates asynchronously via the position stream, so use the
    // captured pre-toggle value rather than re-reading the field here.
    if (wasPlaying) unawaited(_savePlaybackState());
  }

  /// Moves `queueIndex` forward per repeat/shuffle-continuation rules.
  /// Returns false if there's nowhere to go (empty queue, or end reached
  /// with repeat off and no random continuation available).
  bool _advanceQueueIndex() {
    if (queue.isEmpty) return false;
    if (queueIndex < queue.length - 1) {
      queueIndex++;
    } else if (repeat) {
      queueIndex = 0;
    } else {
      final continuation = _pickRandomContinuation();
      if (continuation == null) return false;
      queue.add(continuation);
      queueIndex++;
    }
    return true;
  }

  Future<void> skipNext() async {
    if (!_advanceQueueIndex()) {
      await playback.stop();
      return;
    }
    notifyListeners();
    await _playCurrent();
  }

  Future<void> skipPrevious() async {
    if (queue.isEmpty) return;
    if (position.inSeconds > 3) {
      await playback.seek(Duration.zero);
      return;
    }
    if (queueIndex > 0) {
      queueIndex--;
    } else if (repeat) {
      queueIndex = queue.length - 1;
    } else {
      return;
    }
    notifyListeners();
    await _playCurrent();
  }

  Future<void> seek(Duration position) => playback.seek(position);

  /// Seeks by [delta] relative to the current position (negative rewinds),
  /// clamped to the track's bounds — used by the left/right-arrow shortcuts.
  Future<void> seekRelative(Duration delta) async {
    if (currentTrack == null && currentRadioStation == null) return;
    var target = position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await playback.seek(target);
  }

  static const _prefVolume = 'playback.volume';

  void setVolume(double v) {
    volume = v;
    notifyListeners();
    playback.setVolume(v);
    unawaited(_saveVolume(v));
  }

  Future<void> _saveVolume(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefVolume, v);
  }

  Future<void> _restoreVolume() async {
    final prefs = await SharedPreferences.getInstance();
    volume = prefs.getDouble(_prefVolume) ?? volume;
    await playback.setVolume(volume);
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    if (shuffle && queue.isNotEmpty) {
      final current = currentTrack;
      queue = _shuffled(queue, keepFirst: current);
      queueIndex = current == null ? 0 : queue.indexWhere((t) => t.id == current.id);
    }
    notifyListeners();
    _savePlaybackState();
  }

  void toggleRepeat() {
    repeat = !repeat;
    notifyListeners();
    _savePlaybackState();
  }

  List<LibraryTrack> _shuffled(List<LibraryTrack> input, {LibraryTrack? keepFirst}) {
    final rest = input.where((t) => keepFirst == null || t.id != keepFirst.id).toList()..shuffle(Random());
    return keepFirst == null ? rest : [keepFirst, ...rest];
  }

  /// When the queue runs out (and repeat is off), keep the music going with
  /// a random track from a *different* album — like radio/autoplay — rather
  /// than just stopping.
  LibraryTrack? _pickRandomContinuation() {
    if (allTracks.isEmpty) return null;
    final current = currentTrack;
    final otherAlbums = allTracks.where((t) => current == null || t.albumId != current.albumId).toList();
    final pool = otherAlbums.isNotEmpty ? otherAlbums : allTracks;
    return pool[Random().nextInt(pool.length)];
  }

  Future<void> loadLyricsFor(LibraryTrack track) async {
    loadingLyrics = true;
    currentLyrics = ParsedLyrics.empty;
    notifyListeners();

    if (track.lyrics != null && track.lyrics!.trim().isNotEmpty) {
      currentLyrics = LyricsService.parse(track.lyrics!);
      loadingLyrics = false;
      notifyListeners();
      return;
    }

    final fetched = await LyricsService.fetchFromLrclib(
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
    );
    if (currentTrack?.id != track.id) return; // user moved on before fetch finished
    if (fetched != null && !fetched.isEmpty) {
      currentLyrics = fetched;
      final raw = fetched.isSynced
          ? fetched.syncedLines.map((l) => '[${_fmtLrc(l.time)}]${l.text}').join('\n')
          : fetched.plainText!;
      await LibraryDatabase.setLyrics(track.id, raw);
      _replaceTrackEverywhere(track.copyWith(lyrics: raw));
    }
    loadingLyrics = false;
    notifyListeners();
  }

  String _fmtLrc(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$ms';
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themePrefKey);
    if (saved != null) {
      _palette = CartoonPalette.values.firstWhere((p) => p.name == saved, orElse: () => CartoonPalette.sunny);
      notifyListeners();
    }
  }

  Future<void> setPalette(CartoonPalette p) async {
    _palette = p;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKey, p.name);
  }

  Future<void> _loadCustomTheme() async {
    final prefs = await SharedPreferences.getInstance();
    customTheme = CustomThemeConfig(
      backgroundImagePath: prefs.getString('custom.bgImage'),
      background: _colorOrNull(prefs.getInt('custom.background')),
      sidebar: _colorOrNull(prefs.getInt('custom.sidebar')),
      accent: _colorOrNull(prefs.getInt('custom.accent')),
      textColor: _colorOrNull(prefs.getInt('custom.text')),
    );
    notifyListeners();
  }

  Color? _colorOrNull(int? value) => value == null ? null : Color(value);

  Future<void> setCustomTheme(CustomThemeConfig config) async {
    customTheme = config;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (config.backgroundImagePath != null) {
      await prefs.setString('custom.bgImage', config.backgroundImagePath!);
    } else {
      await prefs.remove('custom.bgImage');
    }
    Future<void> saveColor(String key, Color? c) async {
      if (c != null) {
        await prefs.setInt(key, c.toARGB32());
      } else {
        await prefs.remove(key);
      }
    }

    await saveColor('custom.background', config.background);
    await saveColor('custom.sidebar', config.sidebar);
    await saveColor('custom.accent', config.accent);
    await saveColor('custom.text', config.textColor);
  }

  PaletteColors get colors {
    if (_palette == CartoonPalette.custom) return customTheme.toPaletteColors();
    return kPalettes[_palette]!;
  }
}

void unawaited(Future<void> future) {}

/// User-configurable theme: any combination of a background image and
/// custom colors, layered on top of the Sunny palette's defaults for
/// anything left unset.
class CustomThemeConfig {
  final String? backgroundImagePath;
  final Color? background;
  final Color? sidebar;
  final Color? accent;
  final Color? textColor;

  const CustomThemeConfig({
    this.backgroundImagePath,
    this.background,
    this.sidebar,
    this.accent,
    this.textColor,
  });

  CustomThemeConfig copyWith({
    String? backgroundImagePath,
    bool clearImage = false,
    Color? background,
    Color? sidebar,
    Color? accent,
    Color? textColor,
  }) {
    return CustomThemeConfig(
      backgroundImagePath: clearImage ? null : (backgroundImagePath ?? this.backgroundImagePath),
      background: background ?? this.background,
      sidebar: sidebar ?? this.sidebar,
      accent: accent ?? this.accent,
      textColor: textColor ?? this.textColor,
    );
  }

  PaletteColors toPaletteColors() {
    final fallback = kPalettes[CartoonPalette.sunny]!;
    return PaletteColors(
      displayName: 'Custom',
      background: background ?? fallback.background,
      sidebar: sidebar ?? fallback.sidebar,
      accent: accent ?? fallback.accent,
      supportingAccents: fallback.supportingAccents,
      equalizerColors: fallback.equalizerColors,
      textColor: textColor ?? fallback.textColor,
      isDark: false,
      backgroundImagePath: backgroundImagePath,
    );
  }
}
