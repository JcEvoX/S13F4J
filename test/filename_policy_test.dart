import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/data/vault/filename_policy.dart';

void main() {
  group('FilenamePolicy.sanitizeTitle', () {
    test('替换非法字符', () {
      final out = FilenamePolicy.sanitizeTitle('a/b:c*?"<>|d');
      for (final ch in ['/', '\\', ':', '*', '?', '"', '<', '>', '|']) {
        expect(out.contains(ch), isFalse, reason: '不应包含 $ch');
      }
      expect(out, 'a_b_c______d');
    });

    test('移除控制字符并压缩空白', () {
      expect(FilenamePolicy.sanitizeTitle('a\u0000b\u0007c'), 'abc');
      expect(FilenamePolicy.sanitizeTitle('  a   b  '), 'a b');
    });

    test('去掉前导点', () {
      expect(FilenamePolicy.sanitizeTitle('...name'), 'name');
      expect(FilenamePolicy.sanitizeTitle('...'), '未命名');
    });

    test('空标题回退为未命名', () {
      expect(FilenamePolicy.sanitizeTitle('   '), '未命名');
      expect(FilenamePolicy.sanitizeTitle(''), '未命名');
    });

    test('保留名加下划线', () {
      expect(FilenamePolicy.sanitizeTitle('assets'), 'assets_');
      expect(FilenamePolicy.sanitizeTitle('Assets'), 'Assets_');
      // `.notepad` 会被去掉前导点，不再命中保留名。
      expect(FilenamePolicy.sanitizeTitle('.notepad'), 'notepad');
    });

    test('超长标题按 UTF-8 字节截断', () {
      final long = List.filled(300, 'a').join();
      final folder = FilenamePolicy.sanitizeTitle(long, isFolder: true);
      final note = FilenamePolicy.sanitizeTitle(long);
      expect(utf8.encode(folder).length, lessThanOrEqualTo(255));
      expect(utf8.encode(note).length, lessThanOrEqualTo(252));
      expect(folder.length, 255);
    });

    test('emoji 截断不产生半个字符', () {
      final emoji = List.filled(100, '😀').join();
      final out = FilenamePolicy.sanitizeTitle(emoji, isFolder: true);
      expect(utf8.encode(out).length, lessThanOrEqualTo(255));
      expect(out.runes.every((rune) => rune == 0x1F600), isTrue);
      expect(out.runes.length, 63);
    });
  });

  group('FilenamePolicy 其它规则', () {
    test('fileNameFor 依据类型补扩展名', () {
      expect(FilenamePolicy.fileNameFor('笔记', isFolder: false), '笔记.md');
      expect(FilenamePolicy.fileNameFor('笔记', isFolder: true), '笔记');
    });

    test('uniqueTitle 大小写不敏感并递增后缀', () {
      expect(FilenamePolicy.uniqueTitle('A', const {}), 'A');
      expect(FilenamePolicy.uniqueTitle('A', {'A'}), 'A (2)');
      expect(FilenamePolicy.uniqueTitle('A', {'a', 'A (2)'}), 'A (3)');
    });

    test('titleOfPath 与 isNotePath', () {
      expect(FilenamePolicy.titleOfPath('dir/note.md'), 'note');
      expect(FilenamePolicy.titleOfPath('dir/sub'), 'sub');
      expect(FilenamePolicy.titleOfPath('note.md'), 'note');
      expect(FilenamePolicy.isNotePath('note.md'), isTrue);
      expect(FilenamePolicy.isNotePath('note.MD'), isTrue);
      expect(FilenamePolicy.isNotePath('dir'), isFalse);
    });
  });
}
