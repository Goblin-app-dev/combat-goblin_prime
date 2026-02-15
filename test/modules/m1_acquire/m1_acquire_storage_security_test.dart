import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m1_acquire/storage/acquire_storage.dart';

void main() {
  final storage = AcquireStorage();
  final validBytes = Uint8List.fromList([0x01, 0x02, 0x03]);

  group('AcquireStorage path traversal prevention', () {
    setUp(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    tearDown(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    // ── Traversal via rootId ──

    test('rejects rootId with ../ traversal', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.gst,
          externalFileName: 'test.gst',
          rootId: '../escape',
          packId: null,
          fileExtension: '.gst',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    test('rejects rootId with bare .. segment', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.gst,
          externalFileName: 'test.gst',
          rootId: '..',
          packId: null,
          fileExtension: '.gst',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    test('rejects rootId with forward slash', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.gst,
          externalFileName: 'test.gst',
          rootId: 'a/b',
          packId: null,
          fileExtension: '.gst',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    test('rejects rootId with backslash', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.gst,
          externalFileName: 'test.gst',
          rootId: 'a\\b',
          packId: null,
          fileExtension: '.gst',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    test('rejects absolute rootId', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.gst,
          externalFileName: 'test.gst',
          rootId: '/etc/passwd',
          packId: null,
          fileExtension: '.gst',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    test('rejects empty rootId', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.gst,
          externalFileName: 'test.gst',
          rootId: '',
          packId: null,
          fileExtension: '.gst',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    // ── Traversal via packId ──

    test('rejects packId with ../ traversal', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.cat,
          externalFileName: 'test.cat',
          rootId: 'validRoot',
          packId: '../escape',
          fileExtension: '.cat',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    test('rejects packId with forward slash', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.cat,
          externalFileName: 'test.cat',
          rootId: 'validRoot',
          packId: 'a/b',
          fileExtension: '.cat',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    test('rejects absolute packId', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.cat,
          externalFileName: 'test.cat',
          rootId: 'validRoot',
          packId: '/tmp/evil',
          fileExtension: '.cat',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    // ── Mixed separators ──

    test('rejects rootId with mixed separators and traversal', () {
      expect(
        () => storage.storeFile(
          bytes: validBytes,
          fileType: SourceFileType.gst,
          externalFileName: 'test.gst',
          rootId: '..\\..\\etc',
          packId: null,
          fileExtension: '.gst',
        ),
        throwsA(isA<AcquireFailure>()),
      );
    });

    // ── Valid paths still work ──

    test('accepts valid rootId for gst file', () async {
      final metadata = await storage.storeFile(
        bytes: validBytes,
        fileType: SourceFileType.gst,
        externalFileName: 'Warhammer.gst',
        rootId: 'abc123',
        packId: null,
        fileExtension: '.gst',
      );

      expect(metadata.fileId.length, 64); // sha-256 hex
      expect(metadata.storedPath.contains('abc123'), isTrue);
      expect(File(metadata.storedPath).existsSync(), isTrue);
    });

    test('accepts valid rootId and packId for cat file', () async {
      final metadata = await storage.storeFile(
        bytes: validBytes,
        fileType: SourceFileType.cat,
        externalFileName: 'Marines.cat',
        rootId: 'root-456',
        packId: 'pack-789',
        fileExtension: 'cat',
      );

      expect(metadata.fileId.length, 64);
      expect(metadata.storedPath.contains('root-456'), isTrue);
      expect(metadata.storedPath.contains('pack-789'), isTrue);
      expect(File(metadata.storedPath).existsSync(), isTrue);
    });
  });
}
