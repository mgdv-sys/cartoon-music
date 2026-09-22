import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../widgets/album_card.dart';
import '../widgets/cartoon_button.dart';
import 'artist_detail.dart';

enum ArtistSort { titleAsc, artistAsc, recentlyAdded, year }

const Map<ArtistSort, String> kArtistSortLabels = {
  ArtistSort.titleAsc: 'Title (A–Z)',
  ArtistSort.artistAsc: 'Artist (A–Z)',
  ArtistSort.recentlyAdded: 'Recently added',
  ArtistSort.year: 'Year',
};

/// One artist's albums grouped together, so the Artists grid can show one
/// tile per artist instead of one per album.
class _ArtistGroup {
  final String name;
  final List<LibraryAlbum> albums;
  _ArtistGroup(this.name, this.albums);

  int get albumCount => albums.length;
  int get trackCount => albums.fold(0, (sum, a) => sum + a.trackCount);

  /// The artist's most recently *released* album (highest release year,
  /// falling back to the first album when none are dated) — stands in for
  /// "title" and "year" sorting, and for picking cover art.
  LibraryAlbum get _latestRelease {
    final dated = albums.where((a) => a.releaseYear != null).toList();
    final pool = dated.isNotEmpty ? dated : albums;
    return pool.reduce((a, b) => (b.releaseYear ?? 0) >= (a.releaseYear ?? 0) ? b : a);
  }

  String get representativeTitle => _latestRelease.name;
  int? get representativeYear => _latestRelease.releaseYear;
  DateTime get dateAdded => albums.map((a) => a.dateAdded).reduce((a, b) => a.isAfter(b) ? a : b);

  String? get artworkPath {
    for (final album in albums) {
      if (album.artworkPath != null) return album.artworkPath;
    }
    return null;
  }
}

/// Artists grid: one circular tile per distinct artist, grouped from the
/// album list. Tapping an artist opens every song of theirs across albums.
class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  ArtistSort _sort = ArtistSort.artistAsc;

  List<_ArtistGroup> _grouped(List<LibraryAlbum> albums) {
    final byName = <String, List<LibraryAlbum>>{};
    for (final album in albums) {
      byName.putIfAbsent(album.artist, () => []).add(album);
    }
    return byName.entries.map((e) => _ArtistGroup(e.key, e.value)).toList();
  }

  List<_ArtistGroup> _sorted(List<_ArtistGroup> input) {
    final list = List<_ArtistGroup>.from(input);
    switch (_sort) {
      case ArtistSort.artistAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case ArtistSort.titleAsc:
        list.sort((a, b) => a.representativeTitle.toLowerCase().compareTo(b.representativeTitle.toLowerCase()));
      case ArtistSort.recentlyAdded:
        list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case ArtistSort.year:
        list.sort((a, b) => (b.representativeYear ?? 0).compareTo(a.representativeYear ?? 0));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;
    final artists = _sorted(_grouped(app.albums));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Artists', style: CartoonStyle.heading(colors.textColor, size: 28)),
              const Spacer(),
              if (artists.isNotEmpty)
                PopupMenuButton<ArtistSort>(
                  initialValue: _sort,
                  onSelected: (s) => setState(() => _sort = s),
                  itemBuilder: (context) => ArtistSort.values
                      .map((s) => PopupMenuItem(value: s, child: Text(kArtistSortLabels[s]!)))
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
                        Text(kArtistSortLabels[_sort]!, style: CartoonStyle.body(Colors.black, size: 13)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (!app.libraryLoaded)
            const Center(child: CircularProgressIndicator())
          else if (artists.isEmpty)
            Text('Add a music folder from Home to get started.', style: CartoonStyle.body(colors.textColor))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: artists.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemBuilder: (context, i) {
                final artist = artists[i];
                return AlbumCard(
                  isCircular: true,
                  title: artist.name,
                  subtitle: '${artist.albumCount} ${artist.albumCount == 1 ? 'album' : 'albums'} • ${artist.trackCount} songs',
                  // Prefer a real photo of the artist (fetched in the
                  // background after each scan) over one of their album
                  // covers, which is only a fallback until that lookup
                  // finishes — or if the artist couldn't be found online.
                  artworkUrl: app.artistPhoto(artist.name) ?? artist.artworkPath ?? '',
                  size: 130,
                  isPlaying: app.currentTrack?.artist == artist.name,
                  accentColor: colors.accent,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ArtistDetailScreen(artistName: artist.name)),
                  ),
                  onPlay: () {
                    final tracks = app.allTracks.where((t) => t.artist == artist.name).toList();
                    if (tracks.isNotEmpty) app.playTrack(tracks.first, contextQueue: tracks);
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}
