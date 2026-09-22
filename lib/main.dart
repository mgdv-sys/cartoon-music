import 'dart:io' show Platform;
import 'package:audio_service/audio_service.dart';
// audio_service_mpris isn't imported here directly — it registers itself as
// the Linux AudioServicePlatform implementation (MPRIS over D-Bus) via
// Flutter's generated plugin registrant purely by being a dependency, and
// AudioService.init() below picks it up automatically on Linux.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';
import 'audio/local_playback.dart';
import 'state/app_state.dart';
import 'theme/cartoon_style.dart';
import 'screens/root_shell.dart';
import 'widgets/youtube_download_indicator.dart';

/// Whether the embedded web player (used by Radio's web-link stations, e.g.
/// YouTube) can render on this platform. webview_flutter has no desktop
/// backend at all — Android/iOS only. No embedding, no popup window, no
/// browser fallback on Linux desktop: web-link stations there just show as
/// unavailable (see radio.dart) rather than doing something that isn't
/// really "in the app".
final bool webViewAvailable = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Whether the "Play from YouTube link" playlist import (shells out to
/// yt-dlp, see youtube_service.dart) is offered. Restricted to Linux desktop
/// only — yt-dlp is a system binary, not something bundled per-platform.
final bool youtubePlaylistImportAvailable = !kIsWeb && Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // just_audio has no native Linux/Windows backend of its own; media_kit
  // (libmpv) fills that in. No-op on Android/iOS/macOS. Missing libmpv
  // shouldn't take down the whole app — browsing/scanning still works,
  // playback just won't until libmpv-dev is installed.
  try {
    JustAudioMediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('Audio backend unavailable (playback will not work): $e');
  }

  LocalPlayback? playback;
  // audio_service wires playback into a foreground media service + lock
  // screen/notification controls on Android, and (via audio_service_mpris)
  // an MPRIS D-Bus service on Linux — that's what desktop environments
  // route hardware/keyboard media keys (play/pause/next/previous) to.
  if (!kIsWeb && (Platform.isAndroid || Platform.isLinux)) {
    playback = await AudioService.init(
      builder: () => LocalPlayback(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.cartoonmusic.cartoon_music.audio',
        androidNotificationChannelName: 'Playah playback',
        androidNotificationOngoing: true,
      ),
    );
  }

  runApp(CartoonMusicApp(playback: playback));
}

class CartoonMusicApp extends StatefulWidget {
  final LocalPlayback? playback;
  const CartoonMusicApp({super.key, this.playback});

  @override
  State<CartoonMusicApp> createState() => _CartoonMusicAppState();
}

class _CartoonMusicAppState extends State<CartoonMusicApp> with WidgetsBindingObserver {
  late final AppState _appState;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _appState = AppState(playback: widget.playback, scaffoldMessengerKey: _scaffoldMessengerKey);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pick up new files added while the app was backgrounded, without
    // requiring a manual refresh or a full restart.
    if (state == AppLifecycleState.resumed) {
      _appState.rescanAllFolders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: Consumer<AppState>(
        builder: (context, app, _) {
          return MaterialApp(
            title: 'Playah',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: _scaffoldMessengerKey,
            theme: CartoonStyle.themeFrom(app.colors),
            home: const RootShell(),
            // Wraps every screen (including pushed routes) with the YouTube
            // download progress pill, so it stays visible — and everywhere
            // else stays clickable — no matter where the user navigates
            // while a download runs in the background. Also installs the
            // app-wide playback keyboard shortcuts; CallbackShortcuts only
            // sees keys a focused widget didn't already handle. Play/pause is
            // bound to Enter rather than space: EditableText always reports
            // control keys like Enter as handled, but a plain space typed
            // into a text field goes through the platform IME channel
            // instead and isn't marked handled, so it would still reach here.
            builder: (context, child) => CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): app.togglePlayPause,
                const SingleActivator(LogicalKeyboardKey.keyJ): app.skipPrevious,
                const SingleActivator(LogicalKeyboardKey.keyK): app.skipNext,
                const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                    app.seekRelative(const Duration(seconds: -5)),
                const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                    app.seekRelative(const Duration(seconds: 5)),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    app.setVolume((app.volume + 0.05).clamp(0.0, 1.0)),
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    app.setVolume((app.volume - 0.05).clamp(0.0, 1.0)),
              },
              child: Stack(
                children: [
                  ?child,
                  const YoutubeDownloadIndicator(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
