import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

enum _DeleteChoice { libraryOnly, deleteFile }


/// Shared "delete this song" confirmation + action, used from every track
/// dropdown menu (track rows, album detail). Lets the user choose between
/// just removing it from the library (the file on disk is untouched) or
/// deleting the file for good — the latter is irreversible, so it's always
/// the more clearly-marked, non-default option.
Future<void> confirmDeleteTrack(BuildContext context, LibraryTrack track) async {
  final isStream = track.isYoutubeStream;
  final choice = await showDialog<_DeleteChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove "${track.title}"?'),
      content: Text(
        isStream
            ? 'This will remove it from your library.'
            : 'Just take it out of your library, or delete the file from your device for good?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_DeleteChoice.libraryOnly),
          child: const Text('Remove from library'),
        ),
        if (!isStream)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DeleteChoice.deleteFile),
            child: const Text('Delete file', style: TextStyle(color: Colors.red)),
          ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  await context.read<AppState>().deleteTrack(track, deleteFile: choice == _DeleteChoice.deleteFile);
}

/// Same choice as [confirmDeleteTrack], but for every song in an album at
/// once. Returns true if the user went through with either option (so the
/// caller — the album detail screen — knows to navigate back, since the
/// album it was showing no longer exists).
Future<bool> confirmDeleteAlbum(BuildContext context, LibraryAlbum album, int trackCount) async {
  final choice = await showDialog<_DeleteChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove "${album.name}"?'),
      content: Text(
        'This album has $trackCount ${trackCount == 1 ? 'song' : 'songs'}. '
        'Just take them out of your library, or delete the files from your device for good?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_DeleteChoice.libraryOnly),
          child: const Text('Remove from library'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_DeleteChoice.deleteFile),
          child: const Text('Delete files', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return false;
  await context.read<AppState>().deleteAlbum(album, deleteFiles: choice == _DeleteChoice.deleteFile);
  return true;
}
