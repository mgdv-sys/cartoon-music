import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';

/// A small floating pill reporting YouTube download progress, meant to sit
/// in a corner of the whole app (see its use in `main.dart`'s
/// `MaterialApp.builder`) rather than inside any one screen. Unlike the old
/// blocking progress dialog, it only occupies its own corner of the screen
/// — everywhere else stays fully clickable, and it keeps showing even if
/// the user navigates away from the screen the download was started from.
class YoutubeDownloadIndicator extends StatelessWidget {
  const YoutubeDownloadIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.downloadingYoutubePlaylist) return const SizedBox.shrink();

    final total = app.youtubePlaylistDownloadTotal;
    final queued = app.pendingYoutubeDownloads;
    final label = (total > 0
            ? 'Downloading ${app.youtubePlaylistDownloadProgress}/$total'
            : 'Fetching') +
        (queued > 0 ? ' · $queued more queued…' : '…');

    return Positioned(
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: CartoonStyle.stickerDecoration(fill: Colors.white, borderWidth: CartoonStyle.outlineThin),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 10),
                Text(label, style: CartoonStyle.body(Colors.black, size: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
