import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' as mk;

class PlaybackTick {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  const PlaybackTick({required this.isPlaying, required this.position, required this.duration});
}

/// Wraps a single just_audio `AudioPlayer` and doubles as the app's
/// `AudioHandler`, so on Android playback keeps running (and shows lock
/// screen / notification controls) via a foreground media service instead of
/// getting suspended as soon as the app is backgrounded. Queue/shuffle/repeat
/// logic still lives in AppState — this only plays one file at a time and
/// reports position/completion, plus routes OS media-control taps (from the
/// notification, lock screen, or a headset button) back to AppState via the
/// `onNext`/`onPrevious` hooks, since skip logic depends on the queue.
///
/// YouTube stream URLs (`playRemoteUrl`/`loadRemoteUrl`) go through a
/// separate raw `media_kit.Player` ([_ytPlayer]) instead of the just_audio
/// player above. Reason: mpv's built-in `ytdl_hook` script intercepts *any*
/// http(s) URL it's handed — even one this app already resolved via yt-dlp
/// with the correct headers — and redundantly re-resolves it itself through
/// a local relay, which was hanging/failing outright and blocking playback.
/// Disabling that hook needs `mpv_set_property_string("ytdl", "no")`, which
/// just_audio (and just_audio_media_kit underneath it) doesn't expose; the
/// lower-level `media_kit.Player` does via `NativePlayer.setProperty`. Local
/// files and radio stay on the just_audio player, which works fine as-is.
class LocalPlayback extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _completionSub;
  StreamSubscription? _errorSub;
  Timer? _reconnectTimer;

  late final mk.Player _ytPlayer;
  late final Future<void> _ytPlayerReady;
  bool _usingYtPlayer = false;

  void Function(PlaybackTick tick)? onTick;
  void Function()? onTrackComplete;
  void Function()? onNextRequested;
  void Function()? onPreviousRequested;

  /// Called when a local file errors mid-playback (not a stream — those go
  /// through `onStreamReconnecting` instead). The queue has no other way to
  /// find out; without this the player just goes silent and stays stuck on
  /// the broken track until the user manually hits skip.
  void Function()? onPlaybackError;

  /// Called when a live stream drops and a reconnect attempt is starting, and
  /// again (with `false`) once it either succeeds or gives up — lets the UI
  /// show a "reconnecting" state instead of silently going quiet.
  void Function(bool reconnecting)? onStreamReconnecting;

  bool _isStream = false;
  String? _streamUrl;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 6;

  LocalPlayback() {
    _player.positionStream.listen((position) {
      if (_usingYtPlayer) return;
      final tick = PlaybackTick(
        isPlaying: _player.playing,
        position: position,
        duration: _player.duration ?? Duration.zero,
      );
      onTick?.call(tick);
      _publishState(tick);
    });
    _completionSub = _player.processingStateStream.listen((state) {
      if (_usingYtPlayer) return;
      if (state != ProcessingState.completed) return;
      // A live stream can report `completed` when the server closes the
      // connection cleanly (no error thrown) rather than dropping it — that
      // is not a "track finished", it's the same kind of interruption
      // handled below for stream errors, so reconnect instead of treating
      // it as end-of-track (which used to fall through to the queue's
      // onTrackComplete → skipNext, and with an empty queue during radio
      // playback that just stopped playback outright with no recovery).
      if (_isStream) {
        _scheduleReconnect();
      } else {
        onTrackComplete?.call();
      }
    });
    // just_audio delivers mid-playback failures (a live stream's connection
    // dropping, a buffering underrun, a server hiccup) as an error on this
    // stream rather than as a thrown exception from setUrl/play — without
    // this handler those errors were silently swallowed and the stream just
    // went quiet with no attempt to recover, even on a fine connection.
    // Local queue files hit this same path (a corrupt frame, an underrun,
    // a file on a flaky external drive) — previously nothing handled that
    // case, so the queue silently stalled on the broken track until the
    // user manually hit "next".
    _errorSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (_usingYtPlayer) return;
        if (_isStream) {
          _scheduleReconnect();
        } else {
          onPlaybackError?.call();
        }
      },
    );

    // just_audio_media_kit's own ensureInitialized() no-ops on Android/iOS
    // (just_audio has a native backend there, so it never touches media_kit)
    // but _ytPlayer below is a raw media_kit.Player used directly regardless
    // of platform, so media_kit itself still needs its one-time init here.
    mk.MediaKit.ensureInitialized();
    _ytPlayer = mk.Player();
    _ytPlayerReady = _configureYtPlayer();
  }

  /// Disables mpv's built-in `ytdl_hook` on [_ytPlayer] — see the class doc
  /// above — then wires up the same tick/completion/error reporting the
  /// just_audio player gets, gated to only fire while this player is active.
  Future<void> _configureYtPlayer() async {
    await (_ytPlayer.platform as mk.NativePlayer).setProperty('ytdl', 'no');

    _ytPlayer.stream.position.listen((position) {
      if (!_usingYtPlayer) return;
      final tick = PlaybackTick(
        isPlaying: _ytPlayer.state.playing,
        position: position,
        duration: _ytPlayer.state.duration,
      );
      onTick?.call(tick);
      _publishState(tick);
    });
    _ytPlayer.stream.completed.listen((completed) {
      if (!_usingYtPlayer || !completed) return;
      onTrackComplete?.call();
    });
    _ytPlayer.stream.error.listen((_) {
      if (!_usingYtPlayer) return;
      onPlaybackError?.call();
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts || _streamUrl == null) {
      onStreamReconnecting?.call(false);
      return;
    }
    _reconnectAttempts++;
    onStreamReconnecting?.call(true);
    final delay = Duration(seconds: _reconnectAttempts * 2);
    _reconnectTimer = Timer(delay, () async {
      final url = _streamUrl;
      if (!_isStream || url == null) return;
      try {
        await _player.setUrl(url);
        await _player.play();
        _reconnectAttempts = 0;
        onStreamReconnecting?.call(false);
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _publishState(PlaybackTick tick) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        tick.isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: tick.isPlaying,
      updatePosition: tick.position,
      bufferedPosition: tick.position,
    ));
  }

  bool get isPlaying => _usingYtPlayer ? _ytPlayer.state.playing : _player.playing;
  Duration get position => _usingYtPlayer ? _ytPlayer.state.position : _player.position;
  Duration get duration => _usingYtPlayer ? _ytPlayer.state.duration : (_player.duration ?? Duration.zero);

  /// Loads and immediately plays a file, publishing its metadata to the
  /// lock screen / notification.
  Future<void> playFile(
    String path, {
    String? title,
    String? artist,
    String? album,
    String? artworkPath,
    Duration? duration,
  }) async {
    mediaItem.add(MediaItem(
      id: path,
      title: title ?? 'Unknown track',
      artist: artist,
      album: album,
      duration: duration,
      artUri: artworkPath != null ? Uri.file(artworkPath) : null,
    ));
    _isStream = false;
    _streamUrl = null;
    _reconnectTimer?.cancel();
    if (_usingYtPlayer) {
      _usingYtPlayer = false;
      await _ytPlayer.pause();
    }
    await _player.setFilePath(path);
    await _player.play();
  }

  /// Plays a network URL as a regular queue track (a resolved YouTube audio
  /// stream) rather than a radio-style live stream: unlike [playUrl], this
  /// does *not* set `_isStream`, so a mid-playback drop is treated as a
  /// normal playback error (→ skip to next queue track, same as a broken
  /// local file) instead of triggering the reconnect-loop meant for
  /// open-ended live radio, and reaching the end fires `onTrackComplete` so
  /// the queue actually advances.
  Future<void> playRemoteUrl(
    String url, {
    String? title,
    String? artist,
    String? album,
    String? artworkPath,
    Duration? duration,
    Map<String, String>? headers,
  }) async {
    mediaItem.add(MediaItem(
      id: url,
      title: title ?? 'Unknown track',
      artist: artist,
      album: album,
      duration: duration,
      artUri: artworkPath != null ? Uri.file(artworkPath) : null,
    ));
    _isStream = false;
    _streamUrl = null;
    _reconnectTimer?.cancel();
    await _ytPlayerReady;
    if (!_usingYtPlayer) {
      _usingYtPlayer = true;
      await _player.pause();
    }
    await _ytPlayer.open(mk.Media(url, httpHeaders: headers));
  }

  /// Streams a live internet radio URL and starts playing it immediately.
  /// Unlike local files, streams have no known duration, and can drop mid-
  /// playback due to a transient network/server hiccup — see the
  /// `playbackEventStream` error handler above, which auto-reconnects while
  /// this URL stays the current stream.
  Future<void> playUrl(String url, {String? title, String? artist}) async {
    _isStream = true;
    _streamUrl = url;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    if (_usingYtPlayer) {
      _usingYtPlayer = false;
      await _ytPlayer.pause();
    }
    mediaItem.add(MediaItem(id: url, title: title ?? 'Radio', artist: artist));
    await _player.setUrl(url);
    await _player.play();
  }

  /// Same as [loadFile] but for a network URL — used to restore a session
  /// that was last playing an un-downloaded YouTube track without starting
  /// playback immediately. Needs internet to resolve; callers should expect
  /// this to throw when offline and handle it (e.g. leave nothing loaded).
  Future<void> loadRemoteUrl(
    String url, {
    Duration? startAt,
    String? title,
    String? artist,
    String? album,
    String? artworkPath,
    Duration? duration,
    Map<String, String>? headers,
  }) async {
    mediaItem.add(MediaItem(
      id: url,
      title: title ?? 'Unknown track',
      artist: artist,
      album: album,
      duration: duration,
      artUri: artworkPath != null ? Uri.file(artworkPath) : null,
    ));
    _isStream = false;
    _streamUrl = null;
    _reconnectTimer?.cancel();
    await _ytPlayerReady;
    if (!_usingYtPlayer) {
      _usingYtPlayer = true;
      await _player.pause();
    }
    await _ytPlayer.open(mk.Media(url, httpHeaders: headers), play: false);
    if (startAt != null && startAt > Duration.zero) {
      await _ytPlayer.seek(startAt);
    }
  }

  /// Loads a file without starting playback — used to restore the "now
  /// playing" track on app startup so play/pause/seek work immediately
  /// without audio blasting on launch.
  Future<void> loadFile(
    String path, {
    Duration? startAt,
    String? title,
    String? artist,
    String? album,
    String? artworkPath,
    Duration? duration,
  }) async {
    mediaItem.add(MediaItem(
      id: path,
      title: title ?? 'Unknown track',
      artist: artist,
      album: album,
      duration: duration,
      artUri: artworkPath != null ? Uri.file(artworkPath) : null,
    ));
    _isStream = false;
    _streamUrl = null;
    _reconnectTimer?.cancel();
    if (_usingYtPlayer) {
      _usingYtPlayer = false;
      await _ytPlayer.pause();
    }
    await _player.setFilePath(path);
    if (startAt != null && startAt > Duration.zero) {
      await _player.seek(startAt);
    }
  }

  @override
  Future<void> play() => _usingYtPlayer ? _ytPlayer.play() : _player.play();
  Future<void> resume() => play();

  @override
  Future<void> pause() => _usingYtPlayer ? _ytPlayer.pause() : _player.pause();

  @override
  Future<void> stop() async {
    _isStream = false;
    _streamUrl = null;
    _reconnectTimer?.cancel();
    await _player.stop();
    await _ytPlayer.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _usingYtPlayer ? _ytPlayer.seek(position) : _player.seek(position);

  @override
  Future<void> skipToNext() async => onNextRequested?.call();

  @override
  Future<void> skipToPrevious() async => onPreviousRequested?.call();

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0, 1).toDouble();
    await _player.setVolume(clamped);
    await _ytPlayer.setVolume(clamped * 100);
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _completionSub?.cancel();
    await _errorSub?.cancel();
    await _player.dispose();
    await _ytPlayer.dispose();
  }
}
