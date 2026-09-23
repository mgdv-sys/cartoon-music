import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show youtubePlaylistImportAvailable;
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../widgets/cartoon_button.dart';
import '../widgets/playback_scaffold.dart';
import 'track_list_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      context.read<AppState>().createPlaylist(name);
    }
  }

  Future<void> _playFromYoutubeLink(BuildContext context) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Play from YouTube Music link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Paste a YouTube Music song, album, or playlist link'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Play')),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;

    final app = context.read<AppState>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: 16),
            Expanded(child: Text('Loading playlist…')),
          ],
        ),
      ),
    );
    try {
      final result = await app.importYoutubeLink(url);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final message = result.trackCount == 1
          ? 'Playing "${result.name}".'
          : 'Saved "${result.name}" (${result.trackCount} tracks) — playing now.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't play that link: ${_friendlyError(e)}")),
      );
    }
  }

  Future<void> _downloadFromYoutubeLink(BuildContext context) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download from YouTube'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Paste one or more YouTube Music song, album, or playlist links (one per line)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Add to queue')),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;

    // Runs in the background instead of behind a blocking dialog — the
    // small YoutubeDownloadIndicator (shown app-wide, see main.dart) tracks
    // progress instead, so the rest of the app stays clickable and the
    // user can navigate away while it downloads. The result/any error is
    // reported later via a SnackBar from AppState itself.
    final queued = context.read<AppState>().startYoutubeDownload(url);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Queued $queued ${queued == 1 ? 'link' : 'links'} — you can keep using the app.')),
    );
  }

  String _friendlyError(Object e) {
    if (e is FormatException) return e.message;
    return e.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Playlists', style: CartoonStyle.heading(colors.textColor, size: 28)),
              const Spacer(),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (youtubePlaylistImportAvailable) ...[
                    CartoonButton(
                      fill: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      onPressed: (app.importingYoutubePlaylist || app.downloadingYoutubePlaylist)
                          ? null
                          : () => _playFromYoutubeLink(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.smart_display_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text('Play from YouTube link', style: CartoonStyle.body(Colors.black, size: 13)),
                        ],
                      ),
                    ),
                    CartoonButton(
                      fill: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      onPressed: (app.importingYoutubePlaylist && !app.downloadingYoutubePlaylist)
                          ? null
                          : () => _downloadFromYoutubeLink(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.download_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text('Download from YouTube link', style: CartoonStyle.body(Colors.black, size: 13)),
                        ],
                      ),
                    ),
                  ],
                  CartoonButton(
                    fill: colors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    onPressed: () => _createPlaylist(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text('New playlist', style: CartoonStyle.body(Colors.white, size: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (app.playlists.isEmpty)
            Text('No playlists yet — create one above.', style: CartoonStyle.body(colors.textColor))
          else
            for (final playlist in app.playlists)
              _PlaylistTile(
                playlist: playlist,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaybackScaffold(
                    appBar: AppBar(backgroundColor: colors.background, elevation: 0, title: Text(playlist.name)),
                    body: TrackListScreen(
                      title: playlist.name,
                      loader: () => context.read<AppState>().tracksForPlaylist(playlist.id),
                      emptyMessage: 'No tracks in this playlist yet — use the playlist-add icon on any track.',
                      onRemove: (track) => context.read<AppState>().removeTrackFromPlaylist(playlist.id, track),
                    ),
                  ),
                )),
                onDelete: () => app.deletePlaylist(playlist.id),
              ),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PlaylistTile({required this.playlist, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: CartoonStyle.stickerDecoration(fill: Colors.white, borderWidth: CartoonStyle.outlineThin),
        child: Row(
          children: [
            const Icon(Icons.queue_music_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name, style: CartoonStyle.body(Colors.black, size: 15).copyWith(fontWeight: FontWeight.w500)),
                  Text('${playlist.trackCount} tracks', style: CartoonStyle.body(Colors.black54, size: 12)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}
