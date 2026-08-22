import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/library/providers/file_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  group('getLocalVirtualPath', () {
    test('constructs virtual path for files inside folder', () {
      final folder = LocalFolder(
        name: 'local',
        path: '/var/mobile/Documents/local',
      );
      final result = getLocalVirtualPath(
        folder,
        '/var/mobile/Documents/local/Bleach/Episode 1.mp4',
      );
      expect(result, 'local/Bleach/Episode 1.mp4');
    });

    test('constructs virtual path for custom named folder', () {
      final folder = LocalFolder(name: 'Anime', path: '/iCloud/Anime');
      final result = getLocalVirtualPath(
        folder,
        '/iCloud/Anime/Naruto/Episode 01.mkv',
      );
      expect(result, 'Anime/Naruto/Episode 01.mkv');
    });

    test('returns folder name when entity path is the root folder itself', () {
      final folder = LocalFolder(name: 'Anime', path: '/iCloud/Anime');
      final result = getLocalVirtualPath(folder, '/iCloud/Anime');
      expect(result, 'Anime');
    });

    test('does not create a virtual path for an outside entity', () {
      final folder = LocalFolder(name: 'local', path: '/Documents/local');
      final result = getLocalVirtualPath(
        folder,
        '/var/mobile/Documents/other/Chapter 1.cbz',
      );
      expect(result, '/var/mobile/Documents/other/Chapter 1.cbz');
    });
  });

  group('localVirtualPathFromStoredPath', () {
    final folders = [
      LocalFolder(name: 'local', path: '/Documents/local'),
      LocalFolder(name: 'Downloads', path: '/Downloads'),
    ];

    test('preserves already virtualized path', () {
      expect(
        localVirtualPathFromStoredPath('local/Manga/Chapter 1.cbz', folders),
        'local/Manga/Chapter 1.cbz',
      );
      expect(
        localVirtualPathFromStoredPath(
          'Downloads/Anime/Episode 1.mp4',
          folders,
        ),
        'Downloads/Anime/Episode 1.mp4',
      );
    });

    test('virtualizes absolute path matching configured folder', () {
      expect(
        localVirtualPathFromStoredPath(
          '/Documents/local/Manga/Chapter 1.cbz',
          folders,
        ),
        'local/Manga/Chapter 1.cbz',
      );
    });

    test('handles legacy Mangayomi/local paths', () {
      expect(
        localVirtualPathFromStoredPath(
          '/storage/emulated/0/Mangayomi/local/One Piece/Ch.1.cbz',
          folders,
        ),
        'local/One Piece/Ch.1.cbz',
      );
    });

    test('does not virtualize a stale app-container path', () {
      expect(
        localVirtualPathFromStoredPath(
          '/var/mobile/Containers/Data/Application/OLD/Documents/local/One.cbz',
          [
            LocalFolder(
              name: 'local',
              path:
                  '/var/mobile/Containers/Data/Application/NEW/Documents/local',
            ),
          ],
        ),
        '/var/mobile/Containers/Data/Application/OLD/Documents/local/One.cbz',
      );
    });

    test('does not canonicalize traversal into a virtual path', () {
      expect(
        localVirtualPathFromStoredPath(
          'local/../outside/Chapter 1.cbz',
          folders,
        ),
        'local/../outside/Chapter 1.cbz',
      );
    });

    test('recovers a stale iOS container path under the active folder', () {
      expect(
        localVirtualPathFromStoredPath(
          'local/../../../../../../../../private/var/mobile/Containers/Data/Application/OLD/Documents/local/Manga/Chapter.cbz',
          [
            LocalFolder(
              name: 'local',
              path:
                  '/var/mobile/Containers/Data/Application/NEW/Documents/local',
            ),
          ],
        ),
        'local/Manga/Chapter.cbz',
      );
    });

    test('recovers stale paths for custom folder names', () {
      expect(
        localVirtualPathFromStoredPath(
          'Anime/../../../../../../../../private/var/mobile/Containers/Data/Application/OLD/Documents/Anime/Manga/Chapter.cbz',
          [
            LocalFolder(
              name: 'Anime',
              path:
                  '/var/mobile/Containers/Data/Application/NEW/Documents/Anime',
            ),
          ],
        ),
        'Anime/Manga/Chapter.cbz',
      );
    });

    test('recovers /private/var as /var', () {
      expect(
        localVirtualPathFromStoredPath(
          'local/../../../../../../../../var/mobile/Containers/Data/Application/OLD/Documents/local/Manga/Chapter.cbz',
          [
            LocalFolder(
              name: 'local',
              path: '/private/var/mobile/Containers/Data/Application/NEW/Documents/local',
            ),
          ],
        ),
        'local/Manga/Chapter.cbz',
      );
    });

    test('rejects traversal outside the configured folder', () {
      expect(
        localVirtualPathFromStoredPath('local/../../etc/passwd', folders),
        'local/../../etc/passwd',
      );
    });

    test('rejects traversal from an unknown virtual folder', () {
      expect(
        localVirtualPathFromStoredPath(
          'unknown/../../private/var/mobile/Containers/Data/Application/OLD/Documents/local/Manga.cbz',
          folders,
        ),
        'unknown/../../private/var/mobile/Containers/Data/Application/OLD/Documents/local/Manga.cbz',
      );
    });

    test('does not confuse a virtual folder prefix', () {
      expect(
        localVirtualPathFromStoredPath(
          'local-old/../../private/var/mobile/Containers/Data/Application/OLD/Documents/local/Manga.cbz',
          folders,
        ),
        'local-old/../../private/var/mobile/Containers/Data/Application/OLD/Documents/local/Manga.cbz',
      );
    });
  });

  group('resolveLocalArchiveCandidate', () {
    late Directory tempDirectory;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync('archive-path-test');
    });

    tearDown(() {
      tempDirectory.deleteSync(recursive: true);
    });

    test('uses an existing cbz for a missing extensionless candidate', () {
      final candidate = p.join(tempDirectory.path, 'Chapter');
      final archive = File('$candidate.cbz')..writeAsStringSync('cbz');

      expect(resolveLocalArchiveCandidate(candidate), archive.path);
    });

    test('prefers an existing directory over its cbz sibling', () {
      final candidate = p.join(tempDirectory.path, 'Chapter');
      Directory(candidate).createSync();
      File('$candidate.cbz').writeAsStringSync('cbz');

      expect(resolveLocalArchiveCandidate(candidate), candidate);
    });

    test('keeps a candidate unchanged when neither path exists', () {
      final candidate = p.join(tempDirectory.path, 'Chapter');

      expect(resolveLocalArchiveCandidate(candidate), candidate);
    });
  });
}
