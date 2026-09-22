import 'package:flutter_test/flutter_test.dart';
import 'package:cartoon_music/library/youtube_service.dart';

void main() {
  group('extractVideoId', () {
    test('watch URL', () {
      expect(YoutubeService.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });
    test('youtu.be short URL', () {
      expect(YoutubeService.extractVideoId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });
    test('music.youtube.com watch URL', () {
      expect(YoutubeService.extractVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });
    test('bare video id', () {
      expect(YoutubeService.extractVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });
    test('playlist link with no v= is not a video id', () {
      expect(YoutubeService.extractVideoId('https://www.youtube.com/playlist?list=OLAK5uy_album123'), null);
    });
    test('garbage input', () {
      expect(YoutubeService.extractVideoId('not a url at all'), null);
    });
  });

  group('extractPlaylistId still works (album/playlist links)', () {
    test('album playlist link', () {
      expect(YoutubeService.extractPlaylistId('https://music.youtube.com/playlist?list=OLAK5uy_album123'),
          'OLAK5uy_album123');
    });
    test('watch URL with list param (opened from within a playlist)', () {
      expect(YoutubeService.extractPlaylistId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=OLAK5uy_abc123'),
          'OLAK5uy_abc123');
    });
    test('plain watch URL has no playlist id', () {
      expect(YoutubeService.extractPlaylistId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), null);
    });
  });
}
