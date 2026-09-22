import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import '../widgets/sidebar.dart';
import '../widgets/top_bar.dart';
import '../widgets/transport_bar.dart';
import '../widgets/mini_player.dart';
import '../widgets/theme_picker.dart';
import '../widgets/version_label.dart';
import '../widgets/playback_scaffold.dart';
import 'home.dart';
import 'playlists.dart';
import 'most_played.dart';
import 'recently_played.dart';
import 'favorites.dart';
import 'artists.dart';
import 'all_tracks.dart';
import 'search.dart';
import 'now_playing.dart';
import 'track_list_screen.dart';
import 'radio.dart';

/// Top-level responsive shell: sidebar + top bar + transport bar on desktop
/// widths; a nav drawer + docked mini-player on narrower (Android) widths.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  NavSection _section = NavSection.home;
  String _searchQuery = '';

  void _openNowPlaying() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
  }

  void _openThemePicker() {
    showModalBottomSheet(context: context, builder: (_) => const ThemePickerSheet());
  }

  void _openPlaylist(Playlist playlist) {
    final app = context.read<AppState>();
    final colors = app.colors;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaybackScaffold(
        appBar: AppBar(backgroundColor: colors.background, elevation: 0, title: Text(playlist.name)),
        body: TrackListScreen(
          title: playlist.name,
          loader: () => app.tracksForPlaylist(playlist.id),
          emptyMessage: 'No tracks in this playlist yet — use the playlist-add icon on any track.',
          onRemove: (track) => app.removeTrackFromPlaylist(playlist.id, track),
        ),
      ),
    ));
  }

  Future<void> _newPlaylist() async {
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
    if (name != null && name.isNotEmpty && mounted) {
      context.read<AppState>().createPlaylist(name);
    }
  }

  Future<void> _openMobileSearch() async {
    final controller = TextEditingController(text: _searchQuery);
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Songs, albums, artists'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Search')),
        ],
      ),
    );
    if (query != null) setState(() => _searchQuery = query);
  }

  Widget _mainContent() {
    if (_searchQuery.isNotEmpty) return SearchScreen(query: _searchQuery);
    switch (_section) {
      case NavSection.home:
        return const HomeScreen();
      case NavSection.playlists:
        return const PlaylistsScreen();
      case NavSection.artists:
        return const ArtistsScreen();
      case NavSection.mostPlayed:
        return const MostPlayedScreen();
      case NavSection.recentlyPlayed:
        return const RecentlyPlayedScreen();
      case NavSection.favorites:
        return const FavoritesScreen();
      case NavSection.allTracks:
        return const AllTracksScreen();
      case NavSection.radio:
        return const RadioScreen();
    }
  }

  Widget _withBackground(PaletteColors colors, Widget child) {
    if (colors.backgroundImagePath == null) {
      return Container(color: colors.background, child: child);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(File(colors.backgroundImagePath!), fit: BoxFit.cover),
        ),
        Positioned.fill(child: Container(color: colors.background.withValues(alpha: 0.35))),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth >= CartoonStyle.desktopBreakpoint;

      if (isDesktop) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: _withBackground(
            colors,
            Row(
              children: [
                Sidebar(
                  colors: colors,
                  current: _section,
                  onSelect: (s) => setState(() {
                    _section = s;
                    _searchQuery = '';
                  }),
                  onNewPlaylist: _newPlaylist,
                ),
                Expanded(
                  child: Column(
                    children: [
                      TopBar(
                        colors: colors,
                        onSearchChanged: (q) => setState(() => _searchQuery = q),
                        onAvatarTap: _openThemePicker,
                      ),
                      Expanded(child: _mainContent()),
                      TransportBar(app: app, onExpand: _openNowPlaying),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          elevation: 0,
          title: Text('Playah', style: CartoonStyle.heading(colors.textColor, size: 18)),
          actions: [
            IconButton(icon: const Icon(Icons.search_rounded), onPressed: _openMobileSearch),
            IconButton(icon: const Icon(Icons.palette_rounded), onPressed: _openThemePicker),
          ],
        ),
        drawer: Drawer(
          backgroundColor: colors.sidebar,
          child: SafeArea(
            child: ListView(
              children: [
                for (final section in NavSection.values)
                  ListTile(
                    leading: Icon(kNavIcons[section], color: colors.textColor),
                    title: Text(kNavLabels[section]!, style: CartoonStyle.body(colors.textColor)),
                    selected: _section == section,
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _section = section;
                        _searchQuery = '';
                      });
                    },
                  ),
                const Divider(),
                for (final playlist in app.playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.trackCount} tracks'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _openPlaylist(playlist);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('New playlist'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _newPlaylist();
                  },
                ),
                VersionLabel(color: colors.textColor),
              ],
            ),
          ),
        ),
        body: _withBackground(colors, _mainContent()),
        bottomNavigationBar: !app.hasNowPlaying
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: MiniPlayer(app: app, onExpand: _openNowPlaying),
                ),
              ),
      );
    });
  }
}
