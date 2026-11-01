import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/core/storage/namespace_handle.dart';
import 'package:notepad/core/storage/storage_root.dart';

void main() {
  group('StoragePathGuard', () {
    test('拒绝绝对路径与越界片段', () {
      expect(
        () => StoragePathGuard.validate('/abs/path'),
        throwsA(isA<StoragePathException>()),
      );
      expect(
        () => StoragePathGuard.validate(r'C:\abs\path'),
        throwsA(isA<StoragePathException>()),
      );
      expect(
        () => StoragePathGuard.validate('../evil'),
        throwsA(isA<StoragePathException>()),
      );
      expect(
        () => StoragePathGuard.validate('a//b'),
        throwsA(isA<StoragePathException>()),
      );
      expect(
        () => StoragePathGuard.validate(''),
        throwsA(isA<StoragePathException>()),
      );
    });

    test('允许空路径（表示根）与正常相对路径', () {
      expect(StoragePathGuard.validate('', allowEmpty: true), '');
      expect(StoragePathGuard.validate('a/b.md'), 'a/b.md');
    });
  });

  group('NamespaceHandle', () {
    test('只在命名空间内读写', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('notepad_ns_test_');
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });

      final handle = NamespaceHandle(
        namespaceId: 'project',
        root: SandboxRoot(tempDir.path),
        baseRel: 'ns',
      );

      await handle.writeTextAtomic('a.md', 'hello');
      expect(await handle.exists('a.md'), isTrue);
      expect(await handle.readText('a.md'), 'hello');
      expect(handle.metaDir, 'ns/.notepad');
      expect(await handle.list(''), isNotEmpty);
      expect(File('${tempDir.path}/ns/a.md').existsSync(), isTrue);

      // 越界路径直接拒绝，不产生命名空间外的文件。
      expect(
        () => handle.readText('../evil.md'),
        throwsA(isA<StoragePathException>()),
      );
      expect(File('${tempDir.path}/evil.md').existsSync(), isFalse);
    });
  });
}
