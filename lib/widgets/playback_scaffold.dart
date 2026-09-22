import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/now_playing.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import 'mini_player.dart';
import 'transport_bar.dart';

/// A Scaffold that always keeps the "now playing" transport bar (desktop)
/// or mini-player (mobile) visible, so pushed detail screens — Album
/// Detail, Playlist Detail, Search — don't lose access to playback controls
/// the way a bare Scaffold would.
class PlaybackScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;

  const PlaybackScaffold({super.key, this.appBar, required this.body});

  void _openNowPlaying(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= CartoonStyle.desktopBreakpoint;

      if (isDesktop) {
        return Scaffold(
          backgroundColor: colors.background,
          appBar: appBar,
          body: Column(
            children: [
              Expanded(child: body),
              TransportBar(app: app, onExpand: () => _openNowPlaying(context)),
            ],
          ),
        );
      }

      return Scaffold(
        backgroundColor: colors.background,
        appBar: appBar,
        body: body,
        bottomNavigationBar: !app.hasNowPlaying
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: MiniPlayer(app: app, onExpand: () => _openNowPlaying(context)),
                ),
              ),
      );
    });
  }
}
