import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/media_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late File existingFile;
  late String missingPath;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await MediaCacheService.instance.initialize();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_cache_test_');
    existingFile = File(p.join(tempDir.path, 'present.png'));
    await existingFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);
    missingPath = p.join(tempDir.path, 'absent.png');

    MediaCacheService.instance.clearCache();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MediaCacheService.checkPathsExistence', () {
    test('returns empty map for an empty input list', () async {
      final result = await MediaCacheService.instance.checkPathsExistence([]);
      expect(result, isEmpty);
    });

    test(
      'returns true for an existing file and false for a missing one',
      () async {
        final result = await MediaCacheService.instance.checkPathsExistence([
          existingFile.path,
          missingPath,
        ]);
        expect(result[existingFile.path], isTrue);
        expect(result[missingPath], isFalse);
      },
    );

    test('treats empty/whitespace paths as non-existent without isolate '
        'traffic', () async {
      final result = await MediaCacheService.instance.checkPathsExistence([
        '',
        '   ',
        existingFile.path,
      ]);
      expect(result[''], isFalse);
      expect(result['   '], isFalse);
      expect(result[existingFile.path], isTrue);
    });

    test('caches results: a second call for the same paths is served from the '
        'cache (no extra isolate traffic)', () async {
      await MediaCacheService.instance.checkPathsExistence([existingFile.path]);
      final firstStats = MediaCacheService.instance.getCacheStats();
      final cacheSizeAfterFirst = firstStats['cacheSize'] as int;

      // Delete the file behind the cache; cached `true` should still be
      // returned for the next 30 seconds (cache TTL).
      await existingFile.delete();

      final result = await MediaCacheService.instance.checkPathsExistence([
        existingFile.path,
      ]);
      expect(
        result[existingFile.path],
        isTrue,
        reason: 'cached entry should be returned within TTL',
      );

      final secondStats = MediaCacheService.instance.getCacheStats();
      expect(
        secondStats['cacheSize'],
        cacheSizeAfterFirst,
        reason: 'no new entries added on a pure cache hit',
      );
    });

    test('clearCache invalidates cached entries', () async {
      await MediaCacheService.instance.checkPathsExistence([existingFile.path]);
      MediaCacheService.instance.clearCache();
      await existingFile.delete();

      final result = await MediaCacheService.instance.checkPathsExistence([
        existingFile.path,
      ]);
      expect(
        result[existingFile.path],
        isFalse,
        reason: 'after clearCache, the path is re-checked on disk',
      );
    });
  });
}
