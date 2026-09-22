import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import '../widgets/album_card.dart';
import '../widgets/cartoon_button.dart';
import 'album_detail.dart';

enum AlbumSort { artistAsc, titleAsc, recentlyAdded }

const Map<AlbumSort, String> kAlbumSortLabels = {
  AlbumSort.artistAsc: 'Artist (A–Z)',
  AlbumSort.titleAsc: 'Title (A–Z)',
  AlbumSort.recentlyAdded: 'Recently added',
};

/// Home screen: the Albums grid, with Play/Shuffle-all buttons and a way to
/// add more local music folders.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AlbumSort _sort = AlbumSort.artistAsc;

  List<LibraryAlbum> _sorted(List<LibraryAlbum> input) {
    final list = List<LibraryAlbum>.from(input);
    switch (_sort) {
      case AlbumSort.artistAsc:
        list.sort((a, b) {
          final byArtist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return byArtist != 0 ? byArtist : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case AlbumSort.titleAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case AlbumSort.recentlyAdded:
        list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    }
    return list;
  }

  /// Buckets an already-sorted album list into A/B/C… sections keyed by the
  /// first letter of whichever field it's sorted by (title or artist) — a
  /// non-letter (digit, symbol) groups under "#". Relies on `albums` already
  /// being in the matching sort order, so it just has to split, not re-sort.
  Map<String, List<LibraryAlbum>> _sectioned(List<LibraryAlbum> albums) {
    final sections = <String, List<LibraryAlbum>>{};
    for (final album in albums) {
      final key = _sort == AlbumSort.artistAsc ? album.artist : album.name;
      sections.putIfAbsent(_sectionLetter(key), () => []).add(album);
    }
    return sections;
  }

  String _sectionLetter(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return '#';
    final letter = trimmed[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(letter) ? letter : '#';
  }

  Widget _albumGrid(List<LibraryAlbum> albums, AppState app, PaletteColors colors) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: albums.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisSpacing: 20,
        crossAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, i) {
        final album = albums[i];
        return AlbumCard(
          title: album.name,
          subtitle: '${album.artist} • ${album.trackCount} tracks',
          artworkUrl: album.artworkPath ?? '',
          size: 150,
          isPlaying: app.currentTrack?.albumId == album.id,
          accentColor: colors.accent,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
          ),
          onPlay: () => app.playAlbum(album),
        );
      },
    );
  }

  Future<void> _addFolder(BuildContext context) async {
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.audio.request();
      if (!status.isGranted && !context.mounted) return;
      if (!status.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission is needed to read local music files.')),
          );
        }
        return;
      }
    }
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a music folder');
    if (path == null || !context.mounted) return;
    context.read<AppState>().addFolderAndScan(path);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;
    final albums = _sorted(app.albums);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final buttons = Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (app.albums.isNotEmpty)
                    PopupMenuButton<AlbumSort>(
                      initialValue: _sort,
                      onSelected: (s) => setState(() => _sort = s),
                      itemBuilder: (context) => AlbumSort.values
                          .map((s) => PopupMenuItem(value: s, child: Text(kAlbumSortLabels[s]!)))
                          .toList(),
                      child: CartoonButton(
                        fill: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        onPressed: null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text(kAlbumSortLabels[_sort]!, style: CartoonStyle.body(Colors.black, size: 13)),
                          ],
                        ),
                      ),
                    ),
                  CartoonButton(
                    fill: colors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    onPressed: app.allTracks.isEmpty
                        ? null
                        : () => app.playTrack(app.allTracks.first, contextQueue: app.allTracks),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text('Play', style: CartoonStyle.body(Colors.white, size: 13)),
                      ],
                    ),
                  ),
                  CartoonButton(
                    fill: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    onPressed: app.allTracks.isEmpty
                        ? null
                        : () {
                            if (!app.shuffle) app.toggleShuffle();
                            final tracks = List<LibraryTrack>.from(app.allTracks)..shuffle();
                            app.playTrack(tracks.first, contextQueue: tracks);
                          },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shuffle_rounded, size: 18),
                        const SizedBox(width: 6),
                        Text('Shuffle', style: CartoonStyle.body(Colors.black, size: 13)),
                      ],
                    ),
                  ),
                  CartoonButton(
                    circular: true,
                    fill: Colors.white,
                    padding: const EdgeInsets.all(10),
                    onPressed: () => _addFolder(context),
                    child: const Icon(Icons.create_new_folder_rounded, size: 18),
                  ),
                  CartoonButton(
                    circular: true,
                    fill: Colors.white,
                    padding: const EdgeInsets.all(10),
                    onPressed: app.isScanning ? null : () => app.rescanAllFolders(),
                    child: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ],
              );

              // On narrow (phone-width) screens, cramming the title and all
              // four buttons onto one line leaves no breathing room — stack
              // the buttons on their own row instead of squeezing everything
              // in beside the title.
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Albums', style: CartoonStyle.heading(colors.textColor, size: 28)),
                    const SizedBox(height: 14),
                    buttons,
                  ],
                );
              }
              return Row(
                children: [
                  Text('Albums', style: CartoonStyle.heading(colors.textColor, size: 28)),
                  const Spacer(),
                  buttons,
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (!app.libraryLoaded)
            const Center(child: CircularProgressIndicator())
          else if (app.albums.isEmpty)
            _EmptyLibrary(colors: colors, onAddFolder: () => _addFolder(context))
          else if (_sort == AlbumSort.titleAsc || _sort == AlbumSort.artistAsc)
            for (final entry in _sectioned(albums).entries) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(entry.key, style: CartoonStyle.heading(colors.textColor.withValues(alpha: 0.5), size: 16)),
              ),
              _albumGrid(entry.value, app, colors),
              const SizedBox(height: 20),
            ]
          else
            _albumGrid(albums, app, colors),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final dynamic colors;
  final VoidCallback onAddFolder;
  const _EmptyLibrary({required this.colors, required this.onAddFolder});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: CartoonStyle.stickerDecoration(fill: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No music yet', style: CartoonStyle.heading(Colors.black)),
          const SizedBox(height: 8),
          Text(
            'Add a folder full of songs (.mp3, .flac, .wav, .m4a, .aac, .aiff…) to build your library.',
            style: CartoonStyle.body(Colors.black87),
          ),
          const SizedBox(height: 14),
          ElevatedButton(onPressed: onAddFolder, child: const Text('Add music folder')),
        ],
      ),
    );
  }
}
